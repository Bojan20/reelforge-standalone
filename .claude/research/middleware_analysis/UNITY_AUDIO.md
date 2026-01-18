# Unity Audio System — Complete Technical Analysis

> **Analysis Date:** January 2026
> **Engine Version:** Unity 6 (6000.x) / Unity 2022 LTS
> **Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## Executive Summary

Unity's audio system has evolved through multiple generations, from the legacy FMOD-based system to the experimental DSPGraph framework. While Unity provides a complete audio solution out of the box, many professional projects integrate external middleware (FMOD Studio, Wwise) for advanced features. The upcoming DSPGraph represents Unity's attempt to create a modern, job-compatible audio system, though it remains in preview.

**Key Characteristics:**
- **Built-in system** based on legacy FMOD (not FMOD Studio)
- **AudioMixer** for routing and effects
- **DSPGraph** (preview) for DOTS/ECS compatibility
- **Native Plugin SDK** for C++ DSP development
- **Extensive third-party middleware support**

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [AudioClip System](#2-audioclip-system)
3. [AudioSource & Listener](#3-audiosource--listener)
4. [AudioMixer System](#4-audiomixer-system)
5. [3D Sound & Spatialization](#5-3d-sound--spatialization)
6. [Reverb Zones](#6-reverb-zones)
7. [DSPGraph Framework](#7-dspgraph-framework)
8. [Native Audio Plugin SDK](#8-native-audio-plugin-sdk)
9. [Memory Management](#9-memory-management)
10. [Compression & Streaming](#10-compression--streaming)
11. [Voice Management](#11-voice-management)
12. [Scripting API](#12-scripting-api)
13. [Third-Party Integration](#13-third-party-integration)
14. [Platform Specifics](#14-platform-specifics)
15. [Profiling & Optimization](#15-profiling--optimization)
16. [Best Practices](#16-best-practices)
17. [Comparison with Other Engines](#17-comparison-with-other-engines)
18. [FluxForge Integration Points](#18-fluxforge-integration-points)

---

## 1. Architecture Overview

### 1.1 System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   Scripts   │  │  Prefabs    │  │     Scene Objects       │ │
│  │    (C#)     │  │             │  │   (AudioSource, etc.)   │ │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘ │
│         │                │                      │               │
│         └────────────────┼──────────────────────┘               │
│                          ▼                                       │
├─────────────────────────────────────────────────────────────────┤
│                     UNITY AUDIO ENGINE                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    AudioSource System                        ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐ ││
│  │  │  AudioClip    │  │  3D Settings  │  │  Spatialization │ ││
│  │  │  Playback     │  │  Attenuation  │  │  (Plugin)       │ ││
│  │  └───────┬───────┘  └───────┬───────┘  └────────┬────────┘ ││
│  │          │                  │                   │           ││
│  │          └──────────────────┼───────────────────┘           ││
│  │                             ▼                               ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │                     AudioMixer                          │││
│  │  │  ┌─────────┐  ┌─────────────┐  ┌──────────────────────┐│││
│  │  │  │ Groups  │→│   Effects   │→│     Send/Receive      ││││
│  │  │  │         │  │ (Reverb,EQ) │  │     (Routing)        ││││
│  │  │  └─────────┘  └─────────────┘  └──────────────────────┘│││
│  │  │                                         │               │││
│  │  │                                         ▼               │││
│  │  │  ┌─────────────────────────────────────────────────────┐│││
│  │  │  │                  Master Group                       ││││
│  │  │  │  ┌───────────┐  ┌───────────┐  ┌─────────────────┐ ││││
│  │  │  │  │ Snapshot  │→│  Ducking  │→│  Final Output   │ ││││
│  │  │  │  │ Blending  │  │           │  │                 │ ││││
│  │  │  │  └───────────┘  └───────────┘  └─────────────────┘ ││││
│  │  │  └─────────────────────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                     NATIVE AUDIO LAYER                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   FMOD      │  │  Native     │  │  DSPGraph (Preview)     │ │
│  │  (Legacy)   │  │  Plugins    │  │  (DOTS Compatible)      │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                     PLATFORM AUDIO                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   XAudio2   │  │  CoreAudio  │  │      OpenAL/OpenSL      │ │
│  │  (Windows)  │  │   (macOS)   │  │   (Linux/Android)       │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Core Components

| Component | Purpose | Description |
|-----------|---------|-------------|
| **AudioClip** | Audio data container | Stores audio samples, supports streaming |
| **AudioSource** | Playback controller | Plays AudioClips, handles 3D positioning |
| **AudioListener** | Receiver | Represents the "ears" (usually on camera) |
| **AudioMixer** | Routing & effects | Group-based mixing with DSP effects |
| **AudioMixerGroup** | Submix channel | Route sources for group processing |
| **AudioReverbZone** | Environment | Applies reverb based on position |

### 1.3 Audio Settings

```csharp
// Project Settings → Audio
[Serializable]
public class AudioConfiguration
{
    // Output settings
    public int outputSampleRate = 48000;  // System sample rate
    public AudioSpeakerMode speakerMode = AudioSpeakerMode.Stereo;

    // DSP buffer settings
    public int dspBufferSize = 1024;      // Buffer size in samples
    public int numBuffers = 4;            // Number of buffers

    // Voice management
    public int maxRealVoices = 32;        // Maximum playing voices
    public int maxVirtualVoices = 512;    // Maximum virtual voices

    // Quality settings
    public float globalVolume = 1.0f;
    public float rolloffScale = 1.0f;
    public float dopplerFactor = 1.0f;

    // Spatialization
    public AudioSpatializerPlugin spatializerPlugin;
    public AudioAmbisonicDecoderPlugin ambisonicDecoderPlugin;
}
```

---

## 2. AudioClip System

### 2.1 AudioClip Properties

```csharp
// AudioClip - the audio data container
public class AudioClip : Object
{
    // Basic properties
    public float length { get; }          // Duration in seconds
    public int samples { get; }           // Total sample count
    public int channels { get; }          // Number of channels
    public int frequency { get; }         // Sample rate (Hz)

    // Load state
    public AudioClipLoadType loadType { get; }
    public AudioDataLoadState loadState { get; }
    public bool loadInBackground { get; set; }
    public bool preloadAudioData { get; set; }

    // Data access
    public bool GetData(float[] data, int offsetSamples);
    public bool SetData(float[] data, int offsetSamples);

    // Creation
    public static AudioClip Create(string name, int lengthSamples,
                                   int channels, int frequency,
                                   bool stream);
}

// Load types
public enum AudioClipLoadType
{
    DecompressOnLoad,    // Decompress at load time
    CompressedInMemory,  // Keep compressed, decode on play
    Streaming            // Stream from disk
}

// Load states
public enum AudioDataLoadState
{
    Unloaded,
    Loading,
    Loaded,
    Failed
}
```

### 2.2 Import Settings

```csharp
// AudioImporter settings (Editor)
public class AudioImporter : AssetImporter
{
    // Format
    public bool forceToMono;
    public bool loadInBackground;
    public bool preloadAudioData;
    public bool ambisonic;

    // Default settings
    public AudioImporterSampleSettings defaultSampleSettings;

    // Platform overrides
    public AudioImporterSampleSettings GetOverrideSampleSettings(string platform);
    public void SetOverrideSampleSettings(string platform,
                                         AudioImporterSampleSettings settings);
}

// Sample settings per platform
[Serializable]
public struct AudioImporterSampleSettings
{
    public AudioClipLoadType loadType;
    public AudioSampleRateSetting sampleRateSetting;
    public uint sampleRateOverride;
    public AudioCompressionFormat compressionFormat;
    public float quality;  // 0.0 to 1.0
    public int conversionMode;
}

// Compression formats
public enum AudioCompressionFormat
{
    PCM,           // Uncompressed
    Vorbis,        // Ogg Vorbis (good quality, CPU decode)
    ADPCM,         // Adaptive PCM (low CPU, moderate compression)
    MP3,           // MPEG Layer 3
    VAG,           // PlayStation format
    HEVAG,         // PS Vita format
    XMA,           // Xbox format
    AAC,           // Advanced Audio Coding
    GCADPCM,       // GameCube/Wii ADPCM
    ATRAC9         // PlayStation Vita/PS4
}
```

### 2.3 Procedural Audio

```csharp
// Creating AudioClip from code
public class ProceduralAudioExample : MonoBehaviour
{
    private AudioSource audioSource;
    private int sampleRate = 48000;

    void Start()
    {
        audioSource = GetComponent<AudioSource>();

        // Create 1-second audio clip
        AudioClip clip = AudioClip.Create(
            "ProceduralSine",
            sampleRate,           // 1 second of samples
            1,                    // Mono
            sampleRate,           // Sample rate
            false                 // Not streaming
        );

        // Generate sine wave
        float[] samples = new float[sampleRate];
        float frequency = 440.0f;

        for (int i = 0; i < samples.Length; i++)
        {
            float t = (float)i / sampleRate;
            samples[i] = Mathf.Sin(2.0f * Mathf.PI * frequency * t);
        }

        clip.SetData(samples, 0);
        audioSource.clip = clip;
        audioSource.Play();
    }
}

// Streaming procedural audio with OnAudioFilterRead
public class StreamingProceduralAudio : MonoBehaviour
{
    private float frequency = 440.0f;
    private float phase = 0.0f;
    private float gain = 0.5f;

    void OnAudioFilterRead(float[] data, int channels)
    {
        // Called on audio thread - be careful!
        float sampleRate = AudioSettings.outputSampleRate;
        float increment = frequency / sampleRate;

        for (int i = 0; i < data.Length; i += channels)
        {
            float sample = Mathf.Sin(phase * 2.0f * Mathf.PI) * gain;

            for (int c = 0; c < channels; c++)
            {
                data[i + c] = sample;
            }

            phase += increment;
            if (phase > 1.0f) phase -= 1.0f;
        }
    }
}
```

---

## 3. AudioSource & Listener

### 3.1 AudioSource Component

```csharp
// AudioSource - controls audio playback
public class AudioSource : Behaviour
{
    // Clip and output
    public AudioClip clip;
    public AudioMixerGroup outputAudioMixerGroup;

    // Playback state
    public bool isPlaying { get; }
    public bool isVirtual { get; }
    public float time { get; set; }         // Playback position in seconds
    public int timeSamples { get; set; }    // Playback position in samples

    // Playback control
    public void Play();
    public void PlayDelayed(float delay);
    public void PlayScheduled(double time);  // DSP time
    public void SetScheduledStartTime(double time);
    public void SetScheduledEndTime(double time);
    public void Stop();
    public void Pause();
    public void UnPause();
    public void PlayOneShot(AudioClip clip, float volumeScale = 1.0f);

    // Volume and pitch
    public float volume;            // 0.0 to 1.0
    public float pitch;             // -3.0 to 3.0
    public bool mute;

    // Looping
    public bool loop;

    // 3D sound settings
    public float spatialBlend;      // 0.0 = 2D, 1.0 = 3D
    public float panStereo;         // -1.0 (left) to 1.0 (right)
    public float reverbZoneMix;     // 0.0 to 1.1 (1.1 = 10% reverb)

    // 3D rolloff settings
    public AudioRolloffMode rolloffMode;
    public float minDistance;
    public float maxDistance;
    public float spread;            // 0 to 360 degrees
    public float dopplerLevel;      // 0.0 to 5.0

    // Custom rolloff curve
    public AnimationCurve GetCustomCurve(AudioSourceCurveType type);
    public void SetCustomCurve(AudioSourceCurveType type, AnimationCurve curve);

    // Spatialization plugin
    public bool spatialize;
    public bool spatializePostEffects;

    // Priority (0 = highest, 256 = lowest)
    public int priority;

    // Bypass effects
    public bool bypassEffects;
    public bool bypassListenerEffects;
    public bool bypassReverbZones;

    // Spectrum/output data
    public void GetSpectrumData(float[] samples, int channel, FFTWindow window);
    public void GetOutputData(float[] samples, int channel);
}

// Rolloff modes
public enum AudioRolloffMode
{
    Logarithmic,    // Realistic falloff
    Linear,         // Constant rate falloff
    Custom          // User-defined curve
}

// Curve types
public enum AudioSourceCurveType
{
    CustomRolloff,
    SpatialBlend,
    ReverbZoneMix,
    Spread
}
```

### 3.2 AudioListener Component

```csharp
// AudioListener - the "ears" in the scene
public class AudioListener : Behaviour
{
    // Global settings
    public static float volume { get; set; }  // Master volume
    public static bool pause { get; set; }    // Pause all audio

    // Velocity for doppler effect
    public AudioVelocityUpdateMode velocityUpdateMode;

    // Output data (all audio being heard)
    public static void GetOutputData(float[] samples, int channel);
    public static void GetSpectrumData(float[] samples, int channel,
                                       FFTWindow window);
}

// Velocity update modes
public enum AudioVelocityUpdateMode
{
    Auto,           // Automatically calculate from transform
    Fixed,          // Use FixedUpdate for calculation
    Dynamic         // Use Update for calculation
}
```

### 3.3 Scheduled Playback

```csharp
// Sample-accurate scheduling using DSP time
public class MusicSequencer : MonoBehaviour
{
    public AudioClip[] clips;
    private AudioSource[] sources;
    private int nextClipIndex = 0;
    private double nextEventTime;

    void Start()
    {
        // Create double-buffered audio sources
        sources = new AudioSource[2];
        for (int i = 0; i < 2; i++)
        {
            sources[i] = gameObject.AddComponent<AudioSource>();
        }

        // Schedule first clip
        nextEventTime = AudioSettings.dspTime + 0.1;
        sources[0].clip = clips[0];
        sources[0].PlayScheduled(nextEventTime);

        nextClipIndex = 1;
    }

    void Update()
    {
        // Schedule next clip before current one ends
        if (AudioSettings.dspTime > nextEventTime - 1.0)
        {
            int sourceIndex = nextClipIndex % 2;
            sources[sourceIndex].clip = clips[nextClipIndex % clips.Length];
            sources[sourceIndex].PlayScheduled(nextEventTime);

            // Calculate next event time (beat-synced)
            nextEventTime += clips[nextClipIndex % clips.Length].length;
            nextClipIndex++;
        }
    }
}
```

---

## 4. AudioMixer System

### 4.1 AudioMixer Structure

```
AudioMixer Hierarchy:

┌─────────────────────────────────────────────────┐
│                  AudioMixer                      │
│  ┌─────────────────────────────────────────────┐│
│  │              Master Group                    ││
│  │  ┌─────────────┐  ┌─────────────────────┐  ││
│  │  │   Effects   │  │   Exposed Params    │  ││
│  │  │  (Limiter)  │  │  (Volume, etc.)     │  ││
│  │  └─────────────┘  └─────────────────────┘  ││
│  │         ▲                                   ││
│  │         │                                   ││
│  │  ┌──────┴──────┬──────────────┬──────────┐ ││
│  │  │             │              │          │ ││
│  │┌─┴───────┐ ┌───┴────┐ ┌──────┴───┐ ┌────┴┐││
│  ││  Music  │ │  SFX   │ │  Voice   │ │ UI  │││
│  ││  Group  │ │ Group  │ │  Group   │ │Group│││
│  │└─────────┘ └────────┘ └──────────┘ └─────┘││
│  │     │          │                          ││
│  │  ┌──┴──┐   ┌───┴───┐                     ││
│  │  │Reverb│  │Weapons│                     ││
│  │  │ Send │  │ Group │                     ││
│  │  └─────┘   └───────┘                     ││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

### 4.2 AudioMixer API

```csharp
// AudioMixer - mixing console
public class AudioMixer : Object
{
    // Output group
    public AudioMixerGroup outputAudioMixerGroup { get; }

    // Parameter control
    public bool SetFloat(string name, float value);
    public bool GetFloat(string name, out float value);
    public bool ClearFloat(string name);

    // Snapshots
    public AudioMixerSnapshot FindSnapshot(string name);
    public void TransitionToSnapshots(AudioMixerSnapshot[] snapshots,
                                      float[] weights,
                                      float timeToReach);

    // Update mode
    public AudioMixerUpdateMode updateMode { get; set; }
}

// AudioMixerGroup - submix channel
public class AudioMixerGroup : Object
{
    public AudioMixer audioMixer { get; }
    public string name { get; }
}

// AudioMixerSnapshot - saved mixer state
public class AudioMixerSnapshot : Object
{
    public AudioMixer audioMixer { get; }

    // Transition to this snapshot
    public void TransitionTo(float timeToReach);
}
```

### 4.3 Built-in Mixer Effects

```csharp
// Available AudioMixer effects:
namespace UnityEngine.Audio
{
    // Dynamics
    // - Compressor (threshold, ratio, attack, release, makeup)
    // - Limiter
    // - Normalize

    // EQ
    // - Lowpass (cutoff, resonance)
    // - Highpass (cutoff, resonance)
    // - Lowpass Simple
    // - Highpass Simple
    // - Parametric EQ

    // Reverb
    // - SFX Reverb (room, reverb, high ratio, low ratio, etc.)

    // Chorus
    // - Chorus (dry mix, wet 1-3, delay, rate, depth)

    // Distortion
    // - Distortion (level)

    // Flanger
    // - Flanger (dry mix, wet mix, depth, rate)

    // Echo
    // - Echo (delay, decay, dry mix, wet mix)

    // Pitch Shifter
    // - Pitch Shifter (pitch, FFT size, overlap)

    // Send/Receive
    // - Send (to another group)
    // - Receive (from send)

    // Ducking
    // - Duck Volume (threshold, ratio, attack, release)
}
```

### 4.4 Exposed Parameters

```csharp
// Controlling mixer from script
public class MixerController : MonoBehaviour
{
    public AudioMixer mixer;

    void Start()
    {
        // Set music volume (exposed parameter "MusicVolume")
        mixer.SetFloat("MusicVolume", -10.0f);  // in dB

        // Fade SFX volume
        StartCoroutine(FadeParameter("SFXVolume", -80.0f, 0.0f, 2.0f));
    }

    IEnumerator FadeParameter(string param, float startValue,
                              float endValue, float duration)
    {
        float elapsed = 0;
        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = elapsed / duration;
            float value = Mathf.Lerp(startValue, endValue, t);
            mixer.SetFloat(param, value);
            yield return null;
        }
        mixer.SetFloat(param, endValue);
    }

    // Convert linear (0-1) to decibels for natural-sounding fades
    public static float LinearToDecibel(float linear)
    {
        if (linear <= 0) return -80f;
        return 20f * Mathf.Log10(linear);
    }

    public static float DecibelToLinear(float dB)
    {
        return Mathf.Pow(10f, dB / 20f);
    }
}
```

### 4.5 Snapshots

```csharp
// Using snapshots for state changes
public class AudioSnapshotManager : MonoBehaviour
{
    public AudioMixer mixer;
    public AudioMixerSnapshot normalSnapshot;
    public AudioMixerSnapshot pausedSnapshot;
    public AudioMixerSnapshot underwaterSnapshot;

    public void EnterPauseMenu()
    {
        // Transition to pause snapshot (lowpass, volume duck)
        pausedSnapshot.TransitionTo(0.5f);
    }

    public void ExitPauseMenu()
    {
        normalSnapshot.TransitionTo(0.3f);
    }

    public void EnterUnderwater()
    {
        underwaterSnapshot.TransitionTo(0.2f);
    }

    // Blend between multiple snapshots
    public void SetMixState(float combatIntensity)
    {
        AudioMixerSnapshot[] snapshots = new AudioMixerSnapshot[]
        {
            normalSnapshot,
            combatSnapshot
        };

        float[] weights = new float[]
        {
            1.0f - combatIntensity,
            combatIntensity
        };

        mixer.TransitionToSnapshots(snapshots, weights, 0.5f);
    }
}
```

---

## 5. 3D Sound & Spatialization

### 5.1 3D Audio Settings

```csharp
// 3D sound configuration
public class Audio3DSettings : MonoBehaviour
{
    private AudioSource source;

    void ConfigureAudioSource()
    {
        source = GetComponent<AudioSource>();

        // Enable 3D spatialization
        source.spatialBlend = 1.0f;  // Full 3D

        // Distance attenuation
        source.rolloffMode = AudioRolloffMode.Logarithmic;
        source.minDistance = 1.0f;   // Full volume within this range
        source.maxDistance = 500.0f; // Silent beyond this range

        // Spread (how wide the sound is)
        source.spread = 0.0f;        // 0 = point source, 360 = omnidirectional

        // Doppler effect
        source.dopplerLevel = 1.0f;  // 0 = off, 1 = normal

        // Reverb mix
        source.reverbZoneMix = 1.0f;

        // Priority (lower = higher priority)
        source.priority = 128;       // Default priority
    }

    // Custom rolloff curve
    void SetCustomRolloff()
    {
        source.rolloffMode = AudioRolloffMode.Custom;

        AnimationCurve rolloff = new AnimationCurve(
            new Keyframe(0, 1),          // Full volume at min distance
            new Keyframe(0.2f, 0.6f),    // 60% at 20% distance
            new Keyframe(0.5f, 0.2f),    // 20% at 50% distance
            new Keyframe(1, 0)           // Silent at max distance
        );

        source.SetCustomCurve(AudioSourceCurveType.CustomRolloff, rolloff);
    }
}
```

### 5.2 Spatialization Plugins

```csharp
// Unity's Spatializer SDK allows custom spatialization
// Built-in options:
// - Default Unity panner (stereo only)
// - Microsoft Spatializer (HoloLens)
// - Steam Audio
// - Resonance Audio (Google)
// - Oculus Audio

// Enable spatializer on AudioSource
[RequireComponent(typeof(AudioSource))]
public class SpatializedSound : MonoBehaviour
{
    void Start()
    {
        AudioSource source = GetComponent<AudioSource>();

        // Enable spatializer plugin
        source.spatialize = true;

        // Apply spatialization after effects (for reverb compatibility)
        source.spatializePostEffects = true;
    }
}

// Project Settings → Audio → Spatializer Plugin
// Select: "MS HRTF Spatializer" or custom plugin
```

### 5.3 HRTF Implementation

```csharp
// Head-Related Transfer Function provides:
// - Accurate direction perception
// - Height perception
// - Front/back differentiation
// - Distance cues through spectral shaping

// Steam Audio Integration Example:
/*
1. Install Steam Audio package from Package Manager
2. Add "Steam Audio Manager" to scene
3. Add "Steam Audio Source" component to AudioSources
4. Configure HRTF interpolation method:
   - Nearest: Lowest CPU, snapping artifacts
   - Bilinear: Medium CPU, smooth interpolation
5. Configure occlusion/transmission settings
*/

// Custom HRTF with SOFA files (Steam Audio)
// - AES standardized format
// - Personal HRTF measurements
// - Configuration: Steam Audio Settings → Custom HRTF
```

### 5.4 Ambisonics

```csharp
// Unity supports Ambisonic audio clips
// Import settings: Enable "Ambisonic" checkbox

// Playing ambisonic audio
public class AmbisonicPlayer : MonoBehaviour
{
    public AudioClip ambisonicClip;  // Must be B-format

    void Start()
    {
        AudioSource source = GetComponent<AudioSource>();
        source.clip = ambisonicClip;

        // Ambisonics are automatically decoded based on:
        // Project Settings → Audio → Ambisonic Decoder Plugin
        source.Play();
    }
}

// Supported formats:
// - 1st order (4 channels): W, X, Y, Z
// - Higher orders require custom decoder plugins
```

---

## 6. Reverb Zones

### 6.1 Audio Reverb Zone Component

```csharp
// AudioReverbZone - environment-based reverb
public class AudioReverbZone : Behaviour
{
    // Boundaries
    public float minDistance;    // Full effect within this range
    public float maxDistance;    // No effect beyond this range

    // Preset
    public AudioReverbPreset reverbPreset;

    // Manual parameters (when preset is User)
    public int room;             // Room effect level (-10000 to 0)
    public int roomHF;           // High frequency effect (-10000 to 0)
    public int roomLF;           // Low frequency effect (-10000 to 0)
    public float decayTime;      // Decay time (0.1 to 20.0)
    public float decayHFRatio;   // HF decay ratio (0.1 to 2.0)
    public int reflections;      // Early reflections (-10000 to 1000)
    public float reflectionsDelay;  // Reflections delay (0 to 0.3)
    public int reverb;           // Late reverb level (-10000 to 2000)
    public float reverbDelay;    // Late reverb delay (0 to 0.1)
    public float HFReference;    // HF reference (1000 to 20000 Hz)
    public float LFReference;    // LF reference (20 to 1000 Hz)
    public float diffusion;      // Echo density (0 to 100)
    public float density;        // Modal density (0 to 100)
}

// Reverb presets
public enum AudioReverbPreset
{
    Off,
    Generic,
    PaddedCell,
    Room,
    Bathroom,
    Livingroom,
    Stoneroom,
    Auditorium,
    Concerthall,
    Cave,
    Arena,
    Hangar,
    CarpetedHallway,
    Hallway,
    StoneCorridor,
    Alley,
    Forest,
    City,
    Mountains,
    Quarry,
    Plain,
    ParkingLot,
    SewerPipe,
    Underwater,
    Drugged,
    Dizzy,
    Psychotic,
    User  // Custom parameters
}
```

### 6.2 Reverb Zone Setup

```csharp
// Setting up reverb zones
public class ReverbZoneManager : MonoBehaviour
{
    void CreateBathroomReverb()
    {
        AudioReverbZone zone = gameObject.AddComponent<AudioReverbZone>();

        zone.reverbPreset = AudioReverbPreset.User;

        // Small, tiled room settings
        zone.minDistance = 1.0f;
        zone.maxDistance = 10.0f;
        zone.room = -1000;
        zone.roomHF = -200;
        zone.decayTime = 1.4f;
        zone.decayHFRatio = 0.5f;
        zone.reflections = -400;
        zone.reflectionsDelay = 0.015f;
        zone.reverb = 500;
        zone.reverbDelay = 0.025f;
        zone.diffusion = 80.0f;
        zone.density = 100.0f;
    }

    void CreateCaveReverb()
    {
        AudioReverbZone zone = gameObject.AddComponent<AudioReverbZone>();

        zone.reverbPreset = AudioReverbPreset.Cave;
        zone.minDistance = 5.0f;
        zone.maxDistance = 50.0f;
    }
}
```

---

## 7. DSPGraph Framework

### 7.1 DSPGraph Overview

DSPGraph is Unity's experimental low-level audio mixing engine designed for DOTS compatibility.

```csharp
// DSPGraph is Unity's new audio rendering technology
// Key features:
// - Written in C# with Jobs System support
// - Burst compiler compatible
// - DOTS/ECS integration
// - Custom DSP kernel development

// Status: Preview (0.1.0-preview.22)
// Note: Development has slowed, future uncertain
```

### 7.2 DSPGraph Architecture

```csharp
using Unity.Audio;
using Unity.Collections;
using Unity.Burst;

// DSPGraph consists of:
// - DSPGraph: Container for the audio graph
// - DSPNode: Processing nodes
// - DSPConnection: Weighted connections between nodes
// - DSPCommandBlock: Command execution system
// - DSPSampleProvider: Audio data provider

// Creating a DSPGraph
public class DSPGraphExample
{
    private DSPGraph graph;
    private AudioOutputHandle outputHandle;

    public void Initialize()
    {
        // Create graph with format settings
        var format = ChannelEnumConverter.GetSoundFormatFromSpeakerMode(
            AudioSettings.speakerMode);
        var channels = ChannelEnumConverter.GetChannelCountFromSoundFormat(format);

        graph = DSPGraph.Create(format, channels, 1024, 48000);

        // Get output handle
        outputHandle = graph.RootDSP;
    }

    public void Dispose()
    {
        graph.Dispose();
    }
}
```

### 7.3 Custom DSP Kernel

```csharp
using Unity.Audio;
using Unity.Burst;
using Unity.Collections;
using Unity.Mathematics;

// Define parameters for the kernel
public enum GainParameters
{
    Gain
}

// Custom gain DSP kernel
[BurstCompile(CompileSynchronously = true)]
public struct GainKernel : IAudioKernel<GainParameters, GainKernel.Providers>
{
    public struct Providers : IAudioKernelProviders<GainParameters>
    {
        // No additional providers needed
    }

    // Process audio
    public void Execute(ref ExecuteContext<GainParameters, Providers> context)
    {
        // Get gain parameter
        float gain = context.Parameters.GetFloat(GainParameters.Gain, 0);

        // Process all output buffers
        for (int outputIndex = 0; outputIndex < context.Outputs.Count; outputIndex++)
        {
            var outputBuffer = context.Outputs.GetSampleBuffer(outputIndex);
            var outputChannels = outputBuffer.Channels;

            for (int channel = 0; channel < outputChannels; channel++)
            {
                var outputSamples = outputBuffer.GetBuffer(channel);

                // Get corresponding input
                if (context.Inputs.Count > 0)
                {
                    var inputBuffer = context.Inputs.GetSampleBuffer(0);
                    var inputSamples = inputBuffer.GetBuffer(channel);

                    // Apply gain
                    for (int i = 0; i < outputSamples.Length; i++)
                    {
                        outputSamples[i] = inputSamples[i] * gain;
                    }
                }
            }
        }
    }

    public void Initialize()
    {
        // Initialization code
    }

    public void Dispose()
    {
        // Cleanup code
    }
}
```

### 7.4 DSPGraph Node Creation

```csharp
// Creating and connecting DSPGraph nodes
public class DSPGraphNodeExample
{
    private DSPGraph graph;
    private DSPNode gainNode;
    private DSPNode mixerNode;

    public void CreateNodes()
    {
        using (var block = graph.CreateCommandBlock())
        {
            // Create gain node
            gainNode = block.CreateDSPNode<GainParameters,
                                           GainKernel.Providers,
                                           GainKernel>();

            // Set initial parameter
            block.SetFloat<GainParameters, GainKernel.Providers, GainKernel>(
                gainNode, GainParameters.Gain, 0.5f);

            // Connect to output
            block.Connect(gainNode, 0, graph.RootDSP, 0);
        }
    }

    public void UpdateGain(float newGain)
    {
        using (var block = graph.CreateCommandBlock())
        {
            block.SetFloat<GainParameters, GainKernel.Providers, GainKernel>(
                gainNode, GainParameters.Gain, newGain);
        }
    }
}
```

---

## 8. Native Audio Plugin SDK

### 8.1 Plugin SDK Overview

```cpp
// Unity Native Audio Plugin SDK
// Location: Unity Editor installation/Data/AudioPluginSDK/

// Key files:
// - AudioPluginInterface.h: Main interface
// - AudioPluginUtil.h: Helper utilities
// - AudioPluginUtil.cpp: Implementation

// Plugin entry point
extern "C" UNITY_AUDIODSP_EXPORT_API
int UnityGetAudioEffectDefinitions(
    UnityAudioEffectDefinition*** definitionsPtr);
```

### 8.2 Plugin Structure

```cpp
// AudioPluginInterface.h - Core structures

// Effect definition
struct UnityAudioEffectDefinition
{
    UInt32 structsize;
    UInt32 paramstructsize;
    UInt32 apiversion;
    UInt32 pluginversion;
    UInt32 channels;
    UInt32 numparameters;
    UInt64 flags;
    char name[32];

    // Callbacks
    UnityAudioEffect_CreateCallback create;
    UnityAudioEffect_ReleaseCallback release;
    UnityAudioEffect_ResetCallback reset;
    UnityAudioEffect_ProcessCallback process;
    UnityAudioEffect_SetPositionCallback setposition;

    // Parameter callbacks
    UnityAudioEffect_SetFloatParameterCallback setfloatparameter;
    UnityAudioEffect_GetFloatParameterCallback getfloatparameter;
    UnityAudioEffect_GetFloatBufferCallback getfloatbuffer;

    // Parameter definitions
    UnityAudioParameterDefinition* paramdefs;
};

// Effect state passed to callbacks
struct UnityAudioEffectState
{
    UInt32 structsize;
    UInt32 samplerate;
    UInt64 currdsptick;
    UInt64 prevdsptick;
    float* sidechainbuffer;
    void* effectdata;           // Your custom data
    UInt32 flags;
    void* internal;

    // Spatializer specific
    float* spatializerdata;
    UInt32 dspbuffersize;
    UInt32 hostapiversion;

    // Ambisonics specific
    float* ambisonicdata;
};
```

### 8.3 Implementing a Native Effect

```cpp
// Example: Simple low-pass filter plugin

#include "AudioPluginUtil.h"
#include <cmath>

namespace LowPassFilter
{
    // Effect data structure
    struct EffectData
    {
        float cutoff;
        float resonance;
        float z1[8];  // Per-channel state
        float z2[8];

        // Filter coefficients
        float a0, a1, a2, b1, b2;
    };

    // Parameter indices
    enum Params
    {
        P_CUTOFF,
        P_RESONANCE,
        P_NUM
    };

    // Create callback
    UNITY_AUDIODSP_RESULT UNITY_AUDIODSP_CALLBACK
    CreateCallback(UnityAudioEffectState* state)
    {
        EffectData* data = new EffectData();
        memset(data, 0, sizeof(EffectData));
        data->cutoff = 5000.0f;
        data->resonance = 0.7f;
        state->effectdata = data;

        // Initialize with default parameters
        InitParametersFromDefinitions(
            InternalRegisterEffectDefinition, data);

        return UNITY_AUDIODSP_OK;
    }

    // Release callback
    UNITY_AUDIODSP_RESULT UNITY_AUDIODSP_CALLBACK
    ReleaseCallback(UnityAudioEffectState* state)
    {
        EffectData* data = (EffectData*)state->effectdata;
        delete data;
        return UNITY_AUDIODSP_OK;
    }

    // Calculate filter coefficients
    void CalculateCoefficients(EffectData* data, float sampleRate)
    {
        float omega = 2.0f * 3.14159f * data->cutoff / sampleRate;
        float sinOmega = sinf(omega);
        float cosOmega = cosf(omega);
        float alpha = sinOmega / (2.0f * data->resonance);

        float a0 = 1.0f + alpha;
        data->a0 = (1.0f - cosOmega) * 0.5f / a0;
        data->a1 = (1.0f - cosOmega) / a0;
        data->a2 = data->a0;
        data->b1 = -2.0f * cosOmega / a0;
        data->b2 = (1.0f - alpha) / a0;
    }

    // Process callback
    UNITY_AUDIODSP_RESULT UNITY_AUDIODSP_CALLBACK
    ProcessCallback(
        UnityAudioEffectState* state,
        float* inbuffer,
        float* outbuffer,
        unsigned int length,
        int inchannels,
        int outchannels)
    {
        EffectData* data = (EffectData*)state->effectdata;

        // Recalculate coefficients if needed
        CalculateCoefficients(data, (float)state->samplerate);

        // Process each channel
        for (int ch = 0; ch < outchannels; ch++)
        {
            float z1 = data->z1[ch];
            float z2 = data->z2[ch];

            for (unsigned int i = 0; i < length; i++)
            {
                int idx = i * outchannels + ch;
                float input = inbuffer[idx];

                // Biquad filter
                float output = data->a0 * input + z1;
                z1 = data->a1 * input - data->b1 * output + z2;
                z2 = data->a2 * input - data->b2 * output;

                outbuffer[idx] = output;
            }

            data->z1[ch] = z1;
            data->z2[ch] = z2;
        }

        return UNITY_AUDIODSP_OK;
    }

    // Parameter set callback
    UNITY_AUDIODSP_RESULT UNITY_AUDIODSP_CALLBACK
    SetFloatParameterCallback(
        UnityAudioEffectState* state,
        int index,
        float value)
    {
        EffectData* data = (EffectData*)state->effectdata;

        switch (index)
        {
            case P_CUTOFF:
                data->cutoff = value;
                break;
            case P_RESONANCE:
                data->resonance = value;
                break;
        }

        return UNITY_AUDIODSP_OK;
    }

    // Register the effect
    int InternalRegisterEffectDefinition(
        UnityAudioEffectDefinition& definition)
    {
        int numparams = P_NUM;

        definition.paramdefs = new UnityAudioParameterDefinition[numparams];

        RegisterParameter(
            definition,
            "Cutoff",
            "Hz",
            20.0f, 20000.0f, 5000.0f,
            1.0f,
            1.0f,
            P_CUTOFF,
            "Filter cutoff frequency"
        );

        RegisterParameter(
            definition,
            "Resonance",
            "",
            0.1f, 10.0f, 0.707f,
            1.0f,
            1.0f,
            P_RESONANCE,
            "Filter resonance (Q)"
        );

        definition.flags = 0;
        return numparams;
    }

    // Define callbacks
    DEFINE_EFFECT("My Low Pass", CreateCallback, ReleaseCallback,
                  ProcessCallback, SetFloatParameterCallback,
                  GetFloatParameterCallback);
}
```

### 8.4 Spatializer Plugin

```cpp
// Spatializer plugins extend the native SDK

// Spatializer-specific data in UnityAudioEffectState->spatializerdata:
struct UnityAudioSpatializerData
{
    float listenermatrix[16];    // Listener world matrix
    float sourcematrix[16];      // Source world matrix
    float spatialblend;          // 2D/3D blend
    float reverbzonemix;         // Reverb send amount
    float spread;                // Source spread angle
    float stereopan;             // Stereo panning
    float minDistance;           // Min attenuation distance
    float maxDistance;           // Max attenuation distance
};

// Access in process callback:
UNITY_AUDIODSP_RESULT ProcessCallback(
    UnityAudioEffectState* state,
    float* inbuffer,
    float* outbuffer,
    unsigned int length,
    int inchannels,
    int outchannels)
{
    UnityAudioSpatializerData* spatData =
        (UnityAudioSpatializerData*)state->spatializerdata;

    // Extract source position from matrix
    float sourceX = spatData->sourcematrix[12];
    float sourceY = spatData->sourcematrix[13];
    float sourceZ = spatData->sourcematrix[14];

    // Calculate direction to source
    // Apply HRTF or other spatialization...

    return UNITY_AUDIODSP_OK;
}
```

---

## 9. Memory Management

### 9.1 Audio Memory Budgets

```csharp
// Audio memory considerations

// 1. AudioClip memory based on settings:
// - PCM uncompressed: samples * channels * sizeof(float) = ~4 bytes/sample
// - Vorbis compressed: ~0.4 bytes/sample (depending on quality)
// - ADPCM compressed: ~1 byte/sample
// - Streaming: ~200KB overhead + small buffer

// Example: 5 minute stereo audio at 48kHz
// PCM: 5 * 60 * 48000 * 2 * 4 = ~115 MB
// Vorbis @ 70%: ~11 MB
// ADPCM: ~29 MB
// Streaming: ~200 KB

// 2. Memory settings in AudioClip import:
public class AudioMemoryExample
{
    void ConfigureAudioMemory()
    {
        // For short SFX (< 1 second): DecompressOnLoad + PCM
        // Fast playback, higher memory

        // For medium clips (1-10 seconds): CompressedInMemory + Vorbis
        // Balanced memory/CPU

        // For long audio (music, VO): Streaming + Vorbis
        // Minimal memory, CPU for decode
    }
}
```

### 9.2 AudioSource Pooling

```csharp
// Object pooling for AudioSources
public class AudioSourcePool : MonoBehaviour
{
    public int poolSize = 32;
    private List<AudioSource> pool = new List<AudioSource>();
    private Queue<AudioSource> available = new Queue<AudioSource>();

    void Awake()
    {
        // Pre-create AudioSources
        for (int i = 0; i < poolSize; i++)
        {
            AudioSource source = gameObject.AddComponent<AudioSource>();
            source.playOnAwake = false;
            pool.Add(source);
            available.Enqueue(source);
        }
    }

    public AudioSource GetSource()
    {
        if (available.Count > 0)
        {
            return available.Dequeue();
        }

        // All sources in use - steal lowest priority
        return StealLowestPrioritySource();
    }

    public void ReturnSource(AudioSource source)
    {
        source.Stop();
        source.clip = null;
        available.Enqueue(source);
    }

    private AudioSource StealLowestPrioritySource()
    {
        AudioSource lowest = null;
        int lowestPriority = 0;

        foreach (var source in pool)
        {
            if (source.isPlaying && source.priority > lowestPriority)
            {
                lowest = source;
                lowestPriority = source.priority;
            }
        }

        if (lowest != null)
        {
            lowest.Stop();
            return lowest;
        }

        return null;
    }
}
```

### 9.3 Async Loading

```csharp
// Asynchronous audio loading
public class AsyncAudioLoader : MonoBehaviour
{
    IEnumerator LoadAudioAsync(string path)
    {
        // Using Resources
        ResourceRequest request = Resources.LoadAsync<AudioClip>(path);
        yield return request;

        if (request.asset != null)
        {
            AudioClip clip = request.asset as AudioClip;
            // Use clip...
        }
    }

    // Using Addressables (recommended)
    async void LoadWithAddressables(string address)
    {
        var handle = Addressables.LoadAssetAsync<AudioClip>(address);
        AudioClip clip = await handle.Task;

        // When done:
        // Addressables.Release(handle);
    }
}
```

---

## 10. Compression & Streaming

### 10.1 Compression Format Comparison

| Format | CPU Usage | Compression | Quality | Best For |
|--------|-----------|-------------|---------|----------|
| **PCM** | Lowest | None (1:1) | Perfect | Short SFX |
| **ADPCM** | Low | 3.5:1 | Good | Medium SFX |
| **Vorbis** | Medium | 10-15:1 | Very Good | Music, VO |
| **MP3** | Medium | 10-15:1 | Good | Mobile |
| **AAC** | Medium | 10-15:1 | Very Good | iOS |

### 10.2 Optimal Settings by Type

```csharp
// Audio Import Settings Recommendations

// SHORT SOUND EFFECTS (< 1 second)
// - Load Type: Decompress On Load
// - Compression: PCM or ADPCM
// - Sample Rate: Original or 22050
// Why: Fast playback, small file anyway

// MEDIUM SOUND EFFECTS (1-5 seconds)
// - Load Type: Compressed In Memory
// - Compression: ADPCM
// - Sample Rate: Original or 22050
// Why: Balance of memory and CPU

// LONG AMBIENT LOOPS (5+ seconds)
// - Load Type: Compressed In Memory
// - Compression: Vorbis (quality 70%)
// - Sample Rate: Original
// Why: Good compression, acceptable CPU

// MUSIC
// - Load Type: Streaming
// - Compression: Vorbis (quality 100%)
// - Sample Rate: Original (44100 or 48000)
// - Note: Only stream one at a time
// Why: Minimal memory footprint

// VOICE/DIALOGUE
// - Load Type: Streaming (long) or Compressed (short)
// - Compression: Vorbis (quality 50-70%)
// - Sample Rate: 22050 (speech doesn't need high freq)
// - Force Mono: Yes
// Why: Speech has limited frequency range
```

### 10.3 Streaming Limitations

```csharp
// Streaming considerations
public class StreamingNotes
{
    // 1. Only one audio stream at a time for best performance
    // Multiple streams cause disk seek thrashing

    // 2. Streaming overhead: ~200KB per streaming clip

    // 3. Streaming adds latency (buffering required)
    // Not suitable for responsive sounds

    // 4. Streaming from compressed formats requires CPU

    // 5. Mobile streaming: Be careful of battery drain
}
```

---

## 11. Voice Management

### 11.1 Voice Limits

```csharp
// Voice management in Unity

// Project Settings → Audio
// - Real Voices: Maximum actually playing (CPU/memory)
// - Virtual Voices: Maximum tracked but silent

// When real voices exceeded:
// 1. Lowest priority voices are virtualized
// 2. Virtualized voices track position (no audio)
// 3. Can become real again when priority allows

// Priority: 0 (highest) to 256 (lowest)
// - 0-128: Reserved for critical sounds
// - 128: Default priority
// - 129-256: Background sounds

public class VoiceManagement : MonoBehaviour
{
    void ConfigurePriorities()
    {
        // Player sounds: highest priority
        playerAudioSource.priority = 0;

        // Important gameplay sounds
        weaponAudioSource.priority = 64;

        // Environmental sounds
        ambientAudioSource.priority = 128;

        // Background detail sounds
        backgroundAudioSource.priority = 200;
    }
}
```

### 11.2 Virtualization

```csharp
// Checking virtualization state
public class VirtualizationMonitor : MonoBehaviour
{
    public AudioSource[] sources;

    void Update()
    {
        foreach (var source in sources)
        {
            if (source.isVirtual)
            {
                // Sound is playing but not audible
                // Position is still tracked
                Debug.Log($"{source.clip.name} is virtualized");
            }
        }
    }
}
```

---

## 12. Scripting API

### 12.1 Common Operations

```csharp
// Audio scripting patterns

public class AudioScriptingExamples : MonoBehaviour
{
    private AudioSource source;

    void Start()
    {
        source = GetComponent<AudioSource>();
    }

    // Play sound with randomization
    public void PlayWithVariation(AudioClip clip)
    {
        source.pitch = Random.Range(0.9f, 1.1f);
        source.volume = Random.Range(0.8f, 1.0f);
        source.PlayOneShot(clip);
    }

    // Fade volume
    public IEnumerator FadeOut(float duration)
    {
        float startVolume = source.volume;

        while (source.volume > 0)
        {
            source.volume -= startVolume * Time.deltaTime / duration;
            yield return null;
        }

        source.Stop();
        source.volume = startVolume;
    }

    // Crossfade between clips
    public IEnumerator CrossFade(AudioClip newClip, float duration)
    {
        AudioSource newSource = gameObject.AddComponent<AudioSource>();
        newSource.clip = newClip;
        newSource.volume = 0;
        newSource.Play();

        float startTime = Time.time;

        while (Time.time < startTime + duration)
        {
            float t = (Time.time - startTime) / duration;
            source.volume = 1 - t;
            newSource.volume = t;
            yield return null;
        }

        source.Stop();
        Destroy(source);
        source = newSource;
    }

    // Get spectrum data for visualization
    public float[] GetSpectrum(int size = 256)
    {
        float[] spectrum = new float[size];
        source.GetSpectrumData(spectrum, 0, FFTWindow.BlackmanHarris);
        return spectrum;
    }

    // Get RMS (loudness) level
    public float GetRMSLevel()
    {
        float[] samples = new float[256];
        source.GetOutputData(samples, 0);

        float sum = 0;
        foreach (float sample in samples)
        {
            sum += sample * sample;
        }

        return Mathf.Sqrt(sum / samples.Length);
    }
}
```

### 12.2 OnAudioFilterRead

```csharp
// Real-time audio processing with OnAudioFilterRead
[RequireComponent(typeof(AudioSource))]
public class AudioProcessor : MonoBehaviour
{
    // Called on audio thread - be careful!
    void OnAudioFilterRead(float[] data, int channels)
    {
        // data: interleaved samples [L0, R0, L1, R1, ...]
        // channels: number of channels (usually 2)

        // Example: Simple gain
        float gain = 0.5f;
        for (int i = 0; i < data.Length; i++)
        {
            data[i] *= gain;
        }
    }
}

// Ring buffer for communication with audio thread
public class AudioThreadCommunication : MonoBehaviour
{
    private const int BUFFER_SIZE = 4096;
    private float[] ringBuffer = new float[BUFFER_SIZE];
    private int writeIndex = 0;
    private volatile int readIndex = 0;

    // Main thread writes
    void Update()
    {
        // Write data to ring buffer (from main thread)
    }

    // Audio thread reads
    void OnAudioFilterRead(float[] data, int channels)
    {
        // Read from ring buffer (audio thread)
    }
}
```

### 12.3 Audio Settings API

```csharp
// Runtime audio configuration
public class AudioConfigExample : MonoBehaviour
{
    void ConfigureAudio()
    {
        // Get current configuration
        AudioConfiguration config = AudioSettings.GetConfiguration();

        // Modify settings
        config.sampleRate = 48000;
        config.dspBufferSize = 512;  // Lower = less latency
        config.speakerMode = AudioSpeakerMode.Stereo;
        config.numRealVoices = 64;
        config.numVirtualVoices = 512;

        // Apply (causes audio reset!)
        AudioSettings.Reset(config);
    }

    // Get DSP time for scheduling
    void ScheduleExample()
    {
        double dspTime = AudioSettings.dspTime;
        // Schedule sounds relative to DSP time for sample-accuracy
    }

    // Monitor output
    void OnAudioConfigurationChanged(bool deviceWasChanged)
    {
        if (deviceWasChanged)
        {
            Debug.Log("Audio device changed");
        }
    }
}
```

---

## 13. Third-Party Integration

### 13.1 FMOD Studio Integration

```csharp
// FMOD Studio provides advanced audio features

// Installation:
// 1. Download FMOD Studio + Unity Integration
// 2. Import package into Unity project
// 3. Configure FMOD Settings

// Basic usage:
using FMODUnity;
using FMOD.Studio;

public class FMODExample : MonoBehaviour
{
    // Event reference (set in inspector)
    [FMODUnity.EventRef]
    public string footstepEvent;

    private EventInstance musicInstance;

    void PlayOneShot()
    {
        // Simple one-shot
        RuntimeManager.PlayOneShot(footstepEvent, transform.position);
    }

    void PlayMusic(string musicEvent)
    {
        // Persistent instance with parameters
        musicInstance = RuntimeManager.CreateInstance(musicEvent);
        musicInstance.start();
    }

    void SetParameter(string paramName, float value)
    {
        // Set FMOD parameter
        musicInstance.setParameterByName(paramName, value);
    }

    void OnDestroy()
    {
        musicInstance.stop(FMOD.Studio.STOP_MODE.ALLOWFADEOUT);
        musicInstance.release();
    }
}
```

### 13.2 Wwise Integration

```csharp
// Wwise provides another middleware option

// Installation:
// 1. Download Wwise Launcher
// 2. Install Unity Integration
// 3. Generate SoundBanks

// Basic usage:
public class WwiseExample : MonoBehaviour
{
    public AK.Wwise.Event footstepEvent;
    public AK.Wwise.RTPC healthRTPC;
    public AK.Wwise.State combatState;

    void PlaySound()
    {
        // Post event
        footstepEvent.Post(gameObject);
    }

    void SetHealth(float health)
    {
        // Set RTPC value
        healthRTPC.SetValue(gameObject, health);
    }

    void EnterCombat()
    {
        // Set state
        combatState.SetValue();
    }

    void LoadBank(string bankName)
    {
        AkBankManager.LoadBank(bankName, false, false);
    }
}
```

### 13.3 Steam Audio

```csharp
// Steam Audio provides advanced spatialization

// Features:
// - HRTF-based binaural audio
// - Physics-based reverb
// - Geometry-based occlusion
// - Real-time ray tracing

// Setup:
// 1. Install Steam Audio package
// 2. Add Steam Audio Manager to scene
// 3. Add Steam Audio components to sources

using SteamAudio;

[RequireComponent(typeof(AudioSource))]
public class SteamAudioExample : MonoBehaviour
{
    private SteamAudioSource steamSource;

    void Start()
    {
        steamSource = GetComponent<SteamAudioSource>();

        // Enable features
        steamSource.occlusion = true;
        steamSource.reflections = true;
        steamSource.directBinaural = true;
    }
}
```

---

## 14. Platform Specifics

### 14.1 Platform Audio Settings

```csharp
// Platform-specific audio configuration

#if UNITY_EDITOR
// Editor: Full quality for testing
#elif UNITY_STANDALONE_WIN
// Windows: XAudio2
// - Low latency possible
// - Full feature support
#elif UNITY_STANDALONE_OSX
// macOS: CoreAudio
// - Excellent latency
// - Full feature support
#elif UNITY_IOS
// iOS: CoreAudio
// - Background audio considerations
// - Audio session categories
#elif UNITY_ANDROID
// Android: OpenSL ES
// - High latency variations (device dependent)
// - Use AAudio on newer devices
#elif UNITY_WEBGL
// WebGL: Web Audio API
// - User interaction required to start
// - Limited features
#elif UNITY_PS5
// PS5: Custom Sony audio
// - Tempest 3D AudioTech
// - Hardware accelerated HRTF
#elif UNITY_GAMECORE_XBOXONE || UNITY_GAMECORE_SCARLETT
// Xbox: XAudio2
// - Hardware accelerated
// - Project Acoustics integration
#elif UNITY_SWITCH
// Switch: Custom Nintendo audio
// - Limited voice count
// - Memory constraints
#endif
```

### 14.2 Mobile Audio Considerations

```csharp
// Mobile-specific audio handling
public class MobileAudioManager : MonoBehaviour
{
    void Start()
    {
        // Handle audio focus changes (Android)
        #if UNITY_ANDROID
        // Audio can be interrupted by calls, other apps
        #endif

        // Handle audio route changes (iOS)
        #if UNITY_IOS
        // Handle headphone connect/disconnect
        #endif
    }

    void OnApplicationPause(bool paused)
    {
        // Handle app backgrounding
        AudioListener.pause = paused;
    }

    void OnApplicationFocus(bool hasFocus)
    {
        // Handle focus changes
        AudioListener.pause = !hasFocus;
    }
}
```

---

## 15. Profiling & Optimization

### 15.1 Profiler Metrics

```csharp
// Unity Profiler - Audio section shows:
// - Playing Sources: Currently playing AudioSources
// - Paused Sources: Paused AudioSources
// - Playing Voices: Real voices being rendered
// - Total Audio CPU: Audio thread CPU usage
// - Audio Memory: Memory used by audio system

// Key metrics to watch:
// - Total Audio CPU < 5% (target)
// - Playing Voices < Max Real Voices
// - No voice stealing of high-priority sounds
```

### 15.2 Optimization Tips

```csharp
public class AudioOptimization
{
    // 1. Use appropriate compression
    void OptimizeCompression()
    {
        // SFX: ADPCM or PCM (fast)
        // Music: Streaming + Vorbis (low memory)
        // VO: Compressed + Vorbis (balanced)
    }

    // 2. Pool AudioSources
    void UsePooling()
    {
        // Don't instantiate AudioSources per sound
        // Use a pool of reusable sources
    }

    // 3. Set proper priorities
    void SetPriorities()
    {
        // Critical sounds: 0-64
        // Normal sounds: 128
        // Background: 192-256
    }

    // 4. Use distance culling
    void SetMaxDistance()
    {
        // Set maxDistance to actual audible range
        // Sources beyond maxDistance virtualize
    }

    // 5. Limit simultaneous streams
    void LimitStreaming()
    {
        // Only one or two streaming clips at a time
        // Use Compressed In Memory for concurrent sounds
    }

    // 6. Reduce mixer effects
    void OptimizeMixer()
    {
        // Remove unused effects
        // Combine effect chains where possible
        // Use snapshots for state changes
    }

    // 7. Force mono for non-spatial sounds
    void UseMono()
    {
        // Voice, UI, background can be mono
        // Saves 50% memory and decode time
    }
}
```

### 15.3 Debug Commands

```csharp
// Audio debugging tools

public class AudioDebug : MonoBehaviour
{
    void OnGUI()
    {
        // Show voice count
        GUILayout.Label($"Playing: {FindObjectsOfType<AudioSource>()
            .Count(s => s.isPlaying)}");

        // Show virtualized count
        GUILayout.Label($"Virtual: {FindObjectsOfType<AudioSource>()
            .Count(s => s.isVirtual)}");
    }
}

// Console commands (requires Debug build):
// AudioSource.Log() - Log audio source state
// AudioMixer.Trace() - Trace mixer routing
```

---

## 16. Best Practices

### 16.1 Architecture

```csharp
// Recommended audio architecture

// 1. Central Audio Manager
public class AudioManager : MonoBehaviour
{
    public static AudioManager Instance { get; private set; }

    public AudioMixer masterMixer;
    private AudioSourcePool sfxPool;
    private AudioSource musicSource;

    void Awake()
    {
        if (Instance == null)
        {
            Instance = this;
            DontDestroyOnLoad(gameObject);
            Initialize();
        }
        else
        {
            Destroy(gameObject);
        }
    }

    public void PlaySFX(AudioClip clip, Vector3 position)
    {
        AudioSource source = sfxPool.GetSource();
        source.transform.position = position;
        source.PlayOneShot(clip);
    }
}

// 2. Sound Data Scriptable Objects
[CreateAssetMenu(fileName = "SoundData", menuName = "Audio/Sound Data")]
public class SoundData : ScriptableObject
{
    public AudioClip clip;
    [Range(0, 1)] public float volume = 1f;
    [Range(0.5f, 1.5f)] public float pitchMin = 1f;
    [Range(0.5f, 1.5f)] public float pitchMax = 1f;
    public AudioMixerGroup mixerGroup;
    public int priority = 128;
}

// 3. Event-driven audio
public class AudioEvents : MonoBehaviour
{
    public static event System.Action<SoundData, Vector3> OnPlaySound;

    public static void Play(SoundData sound, Vector3 position)
    {
        OnPlaySound?.Invoke(sound, position);
    }
}
```

### 16.2 Common Pitfalls

```csharp
// Things to avoid

// ❌ Creating AudioSource per sound
void BadExample()
{
    GameObject go = new GameObject("Sound");
    AudioSource source = go.AddComponent<AudioSource>();
    source.PlayOneShot(clip);
    Destroy(go, clip.length); // Memory churn!
}

// ✅ Use pooling instead
void GoodExample()
{
    AudioSource source = pool.GetSource();
    source.PlayOneShot(clip);
    StartCoroutine(ReturnAfterPlay(source, clip.length));
}

// ❌ Streaming multiple clips
void BadStreaming()
{
    foreach (var clip in musicTracks)
    {
        // All streaming at once = disk thrashing
    }
}

// ❌ Forgetting to set maxDistance
void BadAttenuation()
{
    source.spatialBlend = 1;
    // maxDistance defaults to 500 - may be too far
}

// ❌ Using OnAudioFilterRead for heavy processing
void OnAudioFilterRead(float[] data, int channels)
{
    // This runs on audio thread!
    // Don't: allocate memory, use locks, call Unity API
}
```

---

## 17. Comparison with Other Engines

### 17.1 Unity vs Unreal Audio

| Feature | Unity | Unreal |
|---------|-------|--------|
| **Built-in System** | Good (basic) | Excellent (MetaSounds) |
| **Procedural Audio** | Limited (OnAudioFilterRead) | Excellent (MetaSounds) |
| **Middleware Support** | Excellent | Excellent |
| **3D Audio** | Good (plugins) | Excellent (native) |
| **Music System** | Basic | Quartz (advanced) |
| **Profiling** | Good | Excellent |
| **DOTS/ECS** | Preview (DSPGraph) | N/A |

### 17.2 Unity vs Godot Audio

| Feature | Unity | Godot |
|---------|-------|-------|
| **Ease of Use** | Medium | High |
| **Feature Set** | Extensive | Basic |
| **Middleware** | Full support | Limited |
| **Procedural** | Plugin/code | AudioEffects |
| **3D Audio** | Plugin-based | Built-in |
| **Cost** | Free/Pro | Free (MIT) |

---

## 18. FluxForge Integration Points

### 18.1 Applicable Concepts

| Unity Concept | FluxForge Application |
|---------------|----------------------|
| **AudioMixer** | Bus/routing architecture |
| **Snapshots** | Mix state management |
| **Native Plugin SDK** | Plugin interface design |
| **DSPGraph** | Graph-based processing |
| **Voice virtualization** | Voice management |
| **OnAudioFilterRead** | Real-time DSP callback |

### 18.2 Technical Insights

```rust
// Key lessons from Unity for FluxForge:

// 1. AudioMixer-style routing
pub struct MixerGroup {
    name: String,
    parent: Option<MixerGroupId>,
    children: Vec<MixerGroupId>,
    effects: Vec<Box<dyn Effect>>,
    volume: f32,
    mute: bool,
    solo: bool,
}

// 2. Snapshot system for mix states
pub struct MixerSnapshot {
    name: String,
    parameter_values: HashMap<String, f32>,
}

impl MixerSnapshot {
    pub fn transition_to(&self, mixer: &mut Mixer, duration: f32) {
        // Interpolate all parameters over duration
    }
}

// 3. Native plugin interface (inspired by Unity SDK)
pub trait AudioEffect {
    fn create(&mut self, sample_rate: f32) -> Result<()>;
    fn release(&mut self);
    fn process(&mut self, input: &[f32], output: &mut [f32]);
    fn set_parameter(&mut self, index: u32, value: f32);
    fn get_parameter(&self, index: u32) -> f32;
}

// 4. Voice management with virtualization
pub struct VoiceManager {
    real_voices: Vec<Voice>,
    virtual_voices: Vec<VirtualVoice>,
    max_real: usize,
    max_virtual: usize,
}

impl VoiceManager {
    pub fn allocate(&mut self, priority: u8) -> Option<&mut Voice> {
        // Allocate or steal based on priority
    }

    pub fn virtualize_lowest_priority(&mut self) {
        // Move lowest priority real voice to virtual
    }
}
```

### 18.3 Key Takeaways

1. **AudioMixer is powerful** — Group-based routing with effects chains is essential
2. **Snapshots simplify state** — Pre-defined mix states for game situations
3. **Native plugins extend** — C/C++ interface for custom DSP
4. **Voice virtualization** — Track inaudible sounds without rendering
5. **Middleware often needed** — Unity's built-in system is basic for AAA
6. **DSPGraph shows future** — Jobs-based audio is the direction
7. **Compression matters** — Choose format based on use case

---

## Appendix A: AudioMixer Effect Parameters

```
COMPRESSOR:
- Threshold: -80 to 0 dB
- Attack: 0.1 to 500 ms
- Release: 10 to 5000 ms
- Ratio: 1:1 to 20:1
- Makeup Gain: -20 to 20 dB

LOWPASS:
- Cutoff: 10 to 22000 Hz
- Resonance: 1 to 10

HIGHPASS:
- Cutoff: 10 to 22000 Hz
- Resonance: 1 to 10

SFX REVERB:
- Room: -10000 to 0
- Room HF: -10000 to 0
- Decay Time: 0.1 to 20 s
- Decay HF Ratio: 0.1 to 2.0
- Reflections: -10000 to 1000
- Reflections Delay: 0 to 0.3 s
- Reverb: -10000 to 2000
- Reverb Delay: 0 to 0.1 s
- Diffusion: 0 to 100%
- Density: 0 to 100%
- HF Reference: 1000 to 20000 Hz
- LF Reference: 20 to 1000 Hz

ECHO:
- Delay: 1 to 5000 ms
- Decay: 0 to 1
- Dry Mix: 0 to 1
- Wet Mix: 0 to 1

CHORUS:
- Dry Mix: 0 to 1
- Wet Mix 1/2/3: 0 to 1
- Delay: 0.1 to 100 ms
- Rate: 0 to 20 Hz
- Depth: 0 to 1

DISTORTION:
- Level: 0 to 1

PITCH SHIFTER:
- Pitch: 0.5 to 2.0
- FFT Size: 256 to 4096
- Overlap: 1 to 32
```

---

## Appendix B: References

- [Unity Audio Documentation](https://docs.unity3d.com/Manual/Audio.html)
- [Native Audio Plugin SDK](https://docs.unity3d.com/Manual/AudioMixerNativeAudioPlugin.html)
- [DSPGraph Package](https://docs.unity3d.com/Packages/com.unity.audio.dspgraph@latest)
- [FMOD for Unity](https://www.fmod.com/unity)
- [Wwise Unity Integration](https://www.audiokinetic.com/library/edge/?source=Unity)
- [Steam Audio Unity Plugin](https://valvesoftware.github.io/steam-audio/doc/unity/)
- [Unity Audio Optimization Tips](https://gamedevbeginner.com/unity-audio-optimisation-tips/)

---

*Analysis complete. Document serves as reference for FluxForge audio engine development.*
