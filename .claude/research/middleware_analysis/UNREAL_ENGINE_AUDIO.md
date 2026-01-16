# Unreal Engine Audio System — Complete Technical Analysis

> **Analysis Date:** January 2026
> **Engine Version:** Unreal Engine 5.4+
> **Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## Executive Summary

Unreal Engine's audio system represents a fully integrated, game-engine-native solution that has evolved significantly with UE5. The introduction of **MetaSounds** provides a revolutionary approach to procedural audio with sample-accurate DSP graph processing. Combined with the modernized **Audio Mixer**, **Quartz** quantization system, and comprehensive spatial audio support, UE5 offers a complete audio solution without requiring external middleware.

**Key Differentiators:**
- MetaSounds: Fully procedural, node-based DSP system
- Native integration with gameplay systems (Blueprints, C++)
- No licensing fees (included with engine)
- Sample-accurate timing via Quartz
- Built-in convolution reverb and spatialization

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Audio Mixer System](#2-audio-mixer-system)
3. [MetaSounds Deep Dive](#3-metasounds-deep-dive)
4. [Sound Cue System (Legacy)](#4-sound-cue-system-legacy)
5. [Spatial Audio & Attenuation](#5-spatial-audio--attenuation)
6. [Submix System](#6-submix-system)
7. [Quartz Quantization](#7-quartz-quantization)
8. [Source Effects & DSP](#8-source-effects--dsp)
9. [Audio Components](#9-audio-components)
10. [Synthesis Framework](#10-synthesis-framework)
11. [Convolution Reverb](#11-convolution-reverb)
12. [Audio Modulation System](#12-audio-modulation-system)
13. [Soundscape System](#13-soundscape-system)
14. [Platform Audio](#14-platform-audio)
15. [Memory Management](#15-memory-management)
16. [Profiling & Optimization](#16-profiling--optimization)
17. [Plugin Development](#17-plugin-development)
18. [Comparison with Middleware](#18-comparison-with-middleware)
19. [Best Practices](#19-best-practices)
20. [FluxForge Integration Points](#20-fluxforge-integration-points)

---

## 1. Architecture Overview

### 1.1 System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    GAME THREAD                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  Blueprints │  │    C++      │  │   Gameplay Systems      │ │
│  │  (Visual)   │  │   (Native)  │  │   (Animation, Physics)  │ │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘ │
│         │                │                      │               │
│         └────────────────┼──────────────────────┘               │
│                          ▼                                       │
├─────────────────────────────────────────────────────────────────┤
│                    AUDIO THREAD                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    AUDIO ENGINE                              ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐ ││
│  │  │  MetaSounds   │  │  Sound Cues   │  │  Audio Comps    │ ││
│  │  │  (Procedural) │  │   (Legacy)    │  │  (Gameplay)     │ ││
│  │  └───────┬───────┘  └───────┬───────┘  └────────┬────────┘ ││
│  │          │                  │                   │           ││
│  │          └──────────────────┼───────────────────┘           ││
│  │                             ▼                               ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │                   AUDIO MIXER                           │││
│  │  │  ┌─────────┐  ┌─────────────┐  ┌──────────────────────┐│││
│  │  │  │ Sources │→│ Source FX   │→│ Submix Graph          ││││
│  │  │  │ (Voices)│  │ (Per-voice) │  │ (Routing/Processing) ││││
│  │  │  └─────────┘  └─────────────┘  └──────────────────────┘│││
│  │  │                                         │               │││
│  │  │                                         ▼               │││
│  │  │  ┌─────────────────────────────────────────────────────┐│││
│  │  │  │              MASTER SUBMIX                          ││││
│  │  │  │  ┌───────────┐  ┌───────────┐  ┌─────────────────┐ ││││
│  │  │  │  │ Submix FX │→│ Dynamics  │→│ Final Output    │ ││││
│  │  │  │  │ (Reverb)  │  │ (Limiter) │  │ (Platform)      │ ││││
│  │  │  │  └───────────┘  └───────────┘  └─────────────────┘ ││││
│  │  │  └─────────────────────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                    PLATFORM LAYER                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  XAudio2    │  │  CoreAudio  │  │   Platform-Specific     │ │
│  │  (Windows)  │  │   (macOS)   │  │   (PS5, Xbox, Switch)   │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Core Components

| Component | Purpose | Thread |
|-----------|---------|--------|
| **Audio Engine** | High-level management, asset handling | Game |
| **Audio Mixer** | Low-level DSP, mixing, output | Audio |
| **MetaSounds** | Procedural audio graphs | Audio |
| **Sound Cues** | Legacy event-based playback | Game/Audio |
| **Quartz** | Musical timing/quantization | Audio |
| **Submix** | Bus routing and effects | Audio |

### 1.3 Audio Thread Model

```cpp
// UE5 Audio Thread Architecture
class FAudioThread : public FRunnable
{
public:
    // Audio thread runs at fixed buffer size
    static constexpr int32 DefaultBufferSize = 1024;
    static constexpr int32 MinBufferSize = 256;
    static constexpr int32 MaxBufferSize = 4096;

    // Thread priority
    static constexpr EThreadPriority Priority = TPri_TimeCritical;

    virtual uint32 Run() override
    {
        while (!bStopping)
        {
            // Process audio commands from game thread
            ProcessCommands();

            // Update all active sources
            UpdateSources();

            // Process MetaSounds graphs
            ProcessMetaSounds();

            // Mix through submix graph
            ProcessSubmixes();

            // Output to platform
            OutputBuffer();
        }
        return 0;
    }
};
```

### 1.4 Command Queue System

```cpp
// Thread-safe command queue for Game → Audio communication
class FAudioCommandQueue
{
public:
    // Non-blocking enqueue from game thread
    template<typename CommandType, typename... Args>
    void Enqueue(Args&&... InArgs)
    {
        // Lock-free MPSC queue
        CommandBuffer.Enqueue(
            MakeUnique<CommandType>(Forward<Args>(InArgs)...)
        );
    }

    // Process commands on audio thread
    void ProcessCommands()
    {
        TUniquePtr<FAudioCommand> Command;
        while (CommandBuffer.Dequeue(Command))
        {
            Command->Execute();
        }
    }

private:
    TLockFreePointerListUnordered<FAudioCommand> CommandBuffer;
};
```

---

## 2. Audio Mixer System

### 2.1 Mixer Architecture

The Audio Mixer is UE5's core audio processing system, replacing the legacy audio system.

```cpp
// Audio Mixer core structure
class FAudioMixerSourceManager
{
public:
    // Maximum concurrent sources
    static constexpr int32 MaxSources = 128;  // Configurable

    // Source states
    enum class ESourceState : uint8
    {
        Stopped,
        Playing,
        Paused,
        Stopping,
        FadingIn,
        FadingOut
    };

    struct FSourceInfo
    {
        // Playback state
        ESourceState State;
        float CurrentVolume;
        float TargetVolume;
        float CurrentPitch;

        // Buffer management
        TSharedPtr<FSoundBuffer> Buffer;
        int32 CurrentFrame;
        bool bLooping;

        // Spatial data
        FVector Position;
        FQuat Rotation;
        float AttenuationDistance;

        // Effects chain
        TArray<TUniquePtr<FSourceEffect>> SourceEffects;

        // Submix routing
        TWeakObjectPtr<USoundSubmix> Submix;
    };

    TArray<FSourceInfo> Sources;
};
```

### 2.2 Voice Management

```cpp
// Voice allocation and virtualization
class FVoiceManager
{
public:
    // Voice priority calculation
    float CalculateVoicePriority(const FSourceInfo& Source) const
    {
        float Priority = Source.BasePriority;

        // Distance attenuation factor
        if (Source.bUseAttenuation)
        {
            float DistanceFactor = 1.0f - FMath::Clamp(
                Source.ListenerDistance / Source.MaxDistance,
                0.0f, 1.0f
            );
            Priority *= DistanceFactor;
        }

        // Volume factor
        Priority *= Source.CurrentVolume;

        // Focus factor (sounds in front prioritized)
        if (Source.bUseFocus)
        {
            float FocusFactor = FMath::Max(0.0f,
                FVector::DotProduct(ListenerForward, Source.Direction));
            Priority *= FMath::Lerp(0.5f, 1.0f, FocusFactor);
        }

        return Priority;
    }

    // Virtualization decision
    bool ShouldVirtualize(const FSourceInfo& Source) const
    {
        // Never virtualize non-virtualizable sounds
        if (!Source.bCanVirtualize)
            return false;

        // Virtualize if below audibility threshold
        if (Source.CurrentVolume < VirtualizationThreshold)
            return true;

        // Virtualize if beyond max distance
        if (Source.ListenerDistance > Source.MaxDistance * 1.1f)
            return true;

        return false;
    }

private:
    float VirtualizationThreshold = 0.001f;  // -60 dB
};
```

### 2.3 Buffer Management

```cpp
// Circular buffer for streaming audio
class FAudioStreamBuffer
{
public:
    FAudioStreamBuffer(int32 InNumChannels, int32 InBufferSize)
        : NumChannels(InNumChannels)
        , BufferSize(InBufferSize)
        , WriteIndex(0)
        , ReadIndex(0)
    {
        Buffer.SetNumZeroed(NumChannels * BufferSize);
    }

    // Write samples from decoder (can be called from IO thread)
    int32 Write(const float* Samples, int32 NumSamples)
    {
        int32 SamplesWritten = 0;
        while (SamplesWritten < NumSamples && !IsFull())
        {
            int32 WritePos = WriteIndex.load(std::memory_order_relaxed);
            Buffer[WritePos] = Samples[SamplesWritten++];
            WriteIndex.store((WritePos + 1) % Buffer.Num(),
                           std::memory_order_release);
        }
        return SamplesWritten;
    }

    // Read samples for playback (audio thread only)
    int32 Read(float* OutSamples, int32 NumSamples)
    {
        int32 SamplesRead = 0;
        while (SamplesRead < NumSamples && !IsEmpty())
        {
            int32 ReadPos = ReadIndex.load(std::memory_order_relaxed);
            OutSamples[SamplesRead++] = Buffer[ReadPos];
            ReadIndex.store((ReadPos + 1) % Buffer.Num(),
                          std::memory_order_release);
        }
        return SamplesRead;
    }

private:
    TArray<float> Buffer;
    int32 NumChannels;
    int32 BufferSize;
    std::atomic<int32> WriteIndex;
    std::atomic<int32> ReadIndex;
};
```

### 2.4 Sample Rate Conversion

```cpp
// High-quality sample rate conversion
class FSampleRateConverter
{
public:
    // Supported quality levels
    enum class EQuality : uint8
    {
        Fast,       // Linear interpolation
        Medium,     // 4-point Hermite
        High,       // 16-tap windowed sinc
        Best        // 64-tap windowed sinc
    };

    void SetQuality(EQuality InQuality)
    {
        Quality = InQuality;
        switch (Quality)
        {
            case EQuality::Fast:
                FilterTaps = 2;
                break;
            case EQuality::Medium:
                FilterTaps = 4;
                break;
            case EQuality::High:
                FilterTaps = 16;
                break;
            case EQuality::Best:
                FilterTaps = 64;
                break;
        }
        RegenerateFilterKernel();
    }

    // Process block with resampling
    void Process(const float* Input, int32 InputFrames,
                 float* Output, int32 OutputFrames,
                 double Ratio)
    {
        double Phase = 0.0;
        for (int32 i = 0; i < OutputFrames; ++i)
        {
            Output[i] = InterpolateSample(Input, InputFrames, Phase);
            Phase += Ratio;
        }
    }

private:
    float InterpolateSample(const float* Input, int32 NumSamples,
                           double Phase) const
    {
        int32 Index = FMath::FloorToInt(Phase);
        float Frac = Phase - Index;

        if (Quality == EQuality::Fast)
        {
            // Linear
            return FMath::Lerp(
                GetSample(Input, NumSamples, Index),
                GetSample(Input, NumSamples, Index + 1),
                Frac
            );
        }
        else
        {
            // Windowed sinc
            float Sum = 0.0f;
            int32 HalfTaps = FilterTaps / 2;
            for (int32 t = -HalfTaps; t < HalfTaps; ++t)
            {
                float KernelPhase = Frac - t;
                float KernelValue = Sinc(KernelPhase) *
                                   Window(KernelPhase / HalfTaps);
                Sum += GetSample(Input, NumSamples, Index + t) * KernelValue;
            }
            return Sum;
        }
    }

    EQuality Quality = EQuality::High;
    int32 FilterTaps = 16;
    TArray<float> FilterKernel;
};
```

---

## 3. MetaSounds Deep Dive

### 3.1 MetaSounds Overview

MetaSounds is UE5's revolutionary procedural audio system, providing:

- **Node-based DSP programming** (similar to Max/MSP, PureData)
- **Sample-accurate timing and control**
- **C++ and Blueprint extensibility**
- **Real-time parameter modulation**
- **Procedural generation capabilities**

### 3.2 Graph Architecture

```cpp
// MetaSound Graph Structure
namespace Metasound
{
    // Node interface
    class INode
    {
    public:
        virtual ~INode() = default;

        // Get node metadata
        virtual const FNodeClassMetadata& GetMetadata() const = 0;

        // Get input/output vertices
        virtual TArray<FInputVertex> GetInputs() const = 0;
        virtual TArray<FOutputVertex> GetOutputs() const = 0;

        // Create operator instance
        virtual TUniquePtr<IOperator> CreateOperator(
            const FBuildOperatorParams& Params,
            FBuildResults& Results) const = 0;
    };

    // Operator (runtime execution unit)
    class IOperator
    {
    public:
        virtual ~IOperator() = default;

        // Bind inputs/outputs
        virtual void Bind(FInputBindingData& InputData,
                         FOutputBindingData& OutputData) = 0;

        // Process audio block
        virtual void Execute() = 0;

        // Reset state
        virtual void Reset() {}
    };

    // Data types
    using FAudioBuffer = TArray<float>;
    using FTrigger = bool;
    using FTime = float;  // In seconds
}
```

### 3.3 Built-in Node Categories

```
MetaSounds Node Library:

┌─ GENERATORS ─────────────────────────────────────────────────┐
│  • Oscillators: Sine, Saw, Square, Triangle, Noise          │
│  • Wave Table: Custom waveform playback                      │
│  • Sample Player: WAV/OGG playback with pitch control        │
│  • Granular: Grain cloud synthesis                           │
│  • Noise: White, Pink, Brown noise generators                │
└──────────────────────────────────────────────────────────────┘

┌─ FILTERS ────────────────────────────────────────────────────┐
│  • Biquad: LP, HP, BP, Notch, Peak, Shelf                   │
│  • State Variable: Multi-mode with morphing                  │
│  • One Pole: Simple smoothing filter                         │
│  • Ladder: Moog-style 4-pole filter                          │
│  • Comb: Feedforward/feedback comb                           │
└──────────────────────────────────────────────────────────────┘

┌─ ENVELOPES ──────────────────────────────────────────────────┐
│  • ADSR: Attack, Decay, Sustain, Release                    │
│  • AD: Attack, Decay (one-shot)                              │
│  • AR: Attack, Release                                       │
│  • Trigger Envelope: Sample-accurate trigger response        │
└──────────────────────────────────────────────────────────────┘

┌─ EFFECTS ────────────────────────────────────────────────────┐
│  • Delay: Basic delay with feedback                          │
│  • Chorus: Multi-voice modulated delay                       │
│  • Reverb: Algorithmic reverb                                │
│  • Distortion: Waveshaping, saturation                       │
│  • Compressor: Dynamics processing                           │
│  • Bit Crusher: Lo-fi effect                                 │
└──────────────────────────────────────────────────────────────┘

┌─ MATH ───────────────────────────────────────────────────────┐
│  • Add, Subtract, Multiply, Divide                           │
│  • Mix: Multi-channel mixing                                 │
│  • Clamp, Map Range                                          │
│  • Trigger Logic: And, Or, Not, XOR                          │
│  • Random: Random value generation                           │
└──────────────────────────────────────────────────────────────┘

┌─ TIMING ─────────────────────────────────────────────────────┐
│  • Metronome: Tempo-synced triggers                          │
│  • Delay Line: Sample-accurate delay                         │
│  • Counter: Trigger counting                                 │
│  • Sequencer: Step sequencer                                 │
└──────────────────────────────────────────────────────────────┘
```

### 3.4 Custom Node Implementation

```cpp
// Example: Custom MetaSound oscillator node
namespace Metasound
{
    // Node declaration
    class FSuperSawNode : public FNodeFacade
    {
    public:
        // Metadata
        METASOUND_DECLARE_NODE_CLASSNAME(FSuperSawNode,
            "UE.FluxForge.SuperSaw");

        // Input/Output definitions
        struct FInputs
        {
            METASOUND_INPUT_FLOAT(Frequency, "Frequency",
                "Oscillator frequency in Hz", 440.0f);
            METASOUND_INPUT_FLOAT(Detune, "Detune",
                "Detune amount for unison voices", 0.1f);
            METASOUND_INPUT_INT32(NumVoices, "Voices",
                "Number of unison voices", 7);
            METASOUND_INPUT_TRIGGER(Reset, "Reset",
                "Reset oscillator phase");
        };

        struct FOutputs
        {
            METASOUND_OUTPUT_AUDIO(Audio, "Audio",
                "Output audio signal");
        };

        // Operator implementation
        class FOperator : public TExecutableOperator<FOperator>
        {
        public:
            FOperator(const FOperatorSettings& Settings,
                     FFloatReadRef InFrequency,
                     FFloatReadRef InDetune,
                     FInt32ReadRef InNumVoices,
                     FTriggerReadRef InReset)
                : Frequency(InFrequency)
                , Detune(InDetune)
                , NumVoices(InNumVoices)
                , Reset(InReset)
                , SampleRate(Settings.GetSampleRate())
            {
                Audio = FAudioBufferWriteRef::CreateNew(Settings);
                InitializeVoices();
            }

            void Execute()
            {
                const int32 NumFrames = Audio->Num();
                float* OutputBuffer = Audio->GetData();

                // Check for reset trigger
                Reset->ExecuteBlock(
                    [this](int32 StartFrame, int32 EndFrame)
                    {
                        // Reset all voice phases
                        for (auto& Phase : VoicePhases)
                        {
                            Phase = 0.0f;
                        }
                    },
                    [](int32, int32) {} // No-op for non-trigger frames
                );

                // Process audio
                const float Freq = *Frequency;
                const float Det = *Detune;
                const int32 Voices = FMath::Clamp(*NumVoices, 1, 16);

                for (int32 Frame = 0; Frame < NumFrames; ++Frame)
                {
                    float Sample = 0.0f;

                    for (int32 Voice = 0; Voice < Voices; ++Voice)
                    {
                        // Calculate detuned frequency
                        float VoiceDetune = (Voice - Voices / 2.0f) *
                                           Det / Voices;
                        float VoiceFreq = Freq *
                                         FMath::Pow(2.0f, VoiceDetune / 12.0f);

                        // Generate saw wave
                        float Phase = VoicePhases[Voice];
                        Sample += 2.0f * Phase - 1.0f;  // Saw waveform

                        // Advance phase
                        Phase += VoiceFreq / SampleRate;
                        if (Phase >= 1.0f) Phase -= 1.0f;
                        VoicePhases[Voice] = Phase;
                    }

                    // Normalize
                    OutputBuffer[Frame] = Sample / Voices;
                }
            }

        private:
            void InitializeVoices()
            {
                VoicePhases.SetNum(16);
                for (int32 i = 0; i < 16; ++i)
                {
                    VoicePhases[i] = FMath::FRand();  // Random initial phase
                }
            }

            FFloatReadRef Frequency;
            FFloatReadRef Detune;
            FInt32ReadRef NumVoices;
            FTriggerReadRef Reset;
            FAudioBufferWriteRef Audio;

            float SampleRate;
            TArray<float> VoicePhases;
        };
    };

    // Register node
    METASOUND_REGISTER_NODE(FSuperSawNode);
}
```

### 3.5 MetaSound Source Asset

```cpp
// MetaSound Source - playable audio asset
UCLASS()
class UMetaSoundSource : public USoundBase
{
    GENERATED_BODY()

public:
    // MetaSound graph document
    UPROPERTY(EditAnywhere)
    TObjectPtr<UMetaSoundEditorGraph> Graph;

    // Input parameters exposed to gameplay
    UPROPERTY(EditAnywhere, Category = "Parameters")
    TArray<FMetaSoundParameter> Parameters;

    // Output format
    UPROPERTY(EditAnywhere, Category = "Output")
    int32 NumChannels = 2;

    // Quality settings
    UPROPERTY(EditAnywhere, Category = "Quality")
    int32 BlockSize = 256;

    // Duration (infinite if <= 0)
    UPROPERTY(EditAnywhere, Category = "Playback")
    float Duration = -1.0f;
};

// Runtime parameter interface
struct FMetaSoundParameter
{
    FName Name;
    EMetaSoundDataType Type;  // Float, Int, Bool, Trigger, Audio

    // Default value
    FVariant DefaultValue;

    // Range (for Float/Int)
    float MinValue;
    float MaxValue;
};
```

### 3.6 Graph Execution Model

```cpp
// MetaSound graph execution
class FMetaSoundGraphExecutor
{
public:
    // Initialize from graph document
    void Initialize(const UMetaSoundSource* Source,
                   const FAudioMixerSourceVoice& Voice)
    {
        // Build operator graph
        FBuildOperatorParams Params;
        Params.SampleRate = Voice.SampleRate;
        Params.BlockSize = Source->BlockSize;
        Params.NumChannels = Source->NumChannels;

        FBuildResults Results;
        RootOperator = Source->Graph->CreateOperator(Params, Results);

        // Bind parameters
        for (const auto& Param : Source->Parameters)
        {
            ParameterBindings.Add(Param.Name,
                RootOperator->GetParameterBinding(Param.Name));
        }
    }

    // Execute one audio block
    void Execute(float* OutputBuffer, int32 NumFrames)
    {
        // Process pending parameter changes
        ProcessParameterChanges();

        // Execute graph
        RootOperator->Execute();

        // Copy output
        const FAudioBuffer& Output = RootOperator->GetOutput();
        FMemory::Memcpy(OutputBuffer, Output.GetData(),
                       NumFrames * sizeof(float));
    }

    // Set parameter (thread-safe)
    void SetParameter(FName Name, const FVariant& Value)
    {
        FScopeLock Lock(&ParameterLock);
        PendingParameterChanges.Add({Name, Value});
    }

private:
    TUniquePtr<IOperator> RootOperator;
    TMap<FName, IParameterBinding*> ParameterBindings;

    FCriticalSection ParameterLock;
    TArray<FParameterChange> PendingParameterChanges;
};
```

---

## 4. Sound Cue System (Legacy)

### 4.1 Sound Cue Overview

Sound Cues are the legacy (pre-UE5) event-based audio system. Still supported but not recommended for new projects.

```cpp
// Sound Cue asset
UCLASS()
class USoundCue : public USoundBase
{
    GENERATED_BODY()

public:
    // Root node of the sound cue graph
    UPROPERTY()
    TObjectPtr<USoundNode> FirstNode;

    // Volume/pitch multipliers
    UPROPERTY(EditAnywhere)
    float VolumeMultiplier = 1.0f;

    UPROPERTY(EditAnywhere)
    float PitchMultiplier = 1.0f;

    // Attenuation settings
    UPROPERTY(EditAnywhere)
    TObjectPtr<USoundAttenuation> AttenuationSettings;

    // Concurrency settings
    UPROPERTY(EditAnywhere)
    TObjectPtr<USoundConcurrency> ConcurrencySet;
};
```

### 4.2 Sound Cue Nodes

```cpp
// Available Sound Cue node types
class USoundNode { /* Base class */ };

// Playback nodes
class USoundNodeWavePlayer : public USoundNode
{
    UPROPERTY(EditAnywhere)
    TObjectPtr<USoundWave> SoundWave;

    UPROPERTY(EditAnywhere)
    bool bLooping = false;
};

// Randomization
class USoundNodeRandom : public USoundNode
{
    UPROPERTY(EditAnywhere)
    TArray<TObjectPtr<USoundNode>> ChildNodes;

    UPROPERTY(EditAnywhere)
    TArray<float> Weights;

    UPROPERTY(EditAnywhere)
    bool bRandomizeWithoutReplacement = true;
};

// Modulation
class USoundNodeModulator : public USoundNode
{
    UPROPERTY(EditAnywhere)
    float PitchMin = 0.95f;

    UPROPERTY(EditAnywhere)
    float PitchMax = 1.05f;

    UPROPERTY(EditAnywhere)
    float VolumeMin = 0.95f;

    UPROPERTY(EditAnywhere)
    float VolumeMax = 1.05f;
};

// Mixing
class USoundNodeMixer : public USoundNode
{
    UPROPERTY(EditAnywhere)
    TArray<TObjectPtr<USoundNode>> ChildNodes;

    UPROPERTY(EditAnywhere)
    TArray<float> InputVolumes;
};

// Branching based on parameter
class USoundNodeSwitch : public USoundNode
{
    UPROPERTY(EditAnywhere)
    FName ParameterName;

    UPROPERTY(EditAnywhere)
    TArray<TObjectPtr<USoundNode>> ChildNodes;
};

// Crossfade by distance
class USoundNodeDistanceCrossFade : public USoundNode
{
    UPROPERTY(EditAnywhere)
    TArray<FDistanceDatum> CrossFadeInput;
};
```

### 4.3 Sound Cue vs MetaSounds Comparison

| Feature | Sound Cues | MetaSounds |
|---------|-----------|------------|
| **Timing Accuracy** | Frame-accurate | Sample-accurate |
| **Procedural Audio** | Limited | Full support |
| **DSP Processing** | None | Full DSP graph |
| **Parameter Modulation** | Basic | Real-time, per-sample |
| **Performance** | Higher overhead | Optimized |
| **Extensibility** | Node blueprints | C++ operators |
| **Use Case** | Simple playback | Complex audio design |

---

## 5. Spatial Audio & Attenuation

### 5.1 Attenuation System

```cpp
// Sound attenuation settings
USTRUCT()
struct FSoundAttenuationSettings
{
    GENERATED_BODY()

    // Distance algorithm
    UPROPERTY(EditAnywhere)
    EAttenuationDistanceModel DistanceAlgorithm =
        EAttenuationDistanceModel::Logarithmic;

    // Distance range
    UPROPERTY(EditAnywhere)
    float AttenuationShapeExtents = 400.0f;  // Inner radius

    UPROPERTY(EditAnywhere)
    float FalloffDistance = 3600.0f;  // Outer radius

    // Falloff curve
    UPROPERTY(EditAnywhere)
    FRuntimeFloatCurve CustomAttenuationCurve;

    // Low-pass filtering by distance
    UPROPERTY(EditAnywhere)
    bool bEnableLowPassFilter = true;

    UPROPERTY(EditAnywhere)
    float LPFRadiusMin = 3000.0f;

    UPROPERTY(EditAnywhere)
    float LPFRadiusMax = 6000.0f;

    UPROPERTY(EditAnywhere)
    float LPFFrequencyAtMin = 20000.0f;

    UPROPERTY(EditAnywhere)
    float LPFFrequencyAtMax = 1000.0f;

    // Spatialization
    UPROPERTY(EditAnywhere)
    ESoundSpatializationAlgorithm SpatializationAlgorithm =
        ESoundSpatializationAlgorithm::Default;

    // Occlusion
    UPROPERTY(EditAnywhere)
    bool bEnableOcclusion = false;

    UPROPERTY(EditAnywhere)
    ECollisionChannel OcclusionTraceChannel = ECC_Visibility;
};

// Distance model calculation
float CalculateAttenuation(const FSoundAttenuationSettings& Settings,
                          float Distance)
{
    if (Distance <= Settings.AttenuationShapeExtents)
    {
        return 1.0f;  // Full volume inside inner radius
    }

    float NormalizedDistance = (Distance - Settings.AttenuationShapeExtents) /
                               Settings.FalloffDistance;
    NormalizedDistance = FMath::Clamp(NormalizedDistance, 0.0f, 1.0f);

    switch (Settings.DistanceAlgorithm)
    {
        case EAttenuationDistanceModel::Linear:
            return 1.0f - NormalizedDistance;

        case EAttenuationDistanceModel::Logarithmic:
            return FMath::Max(0.0f,
                1.0f - 0.5f * FMath::Loge(1.0f + NormalizedDistance));

        case EAttenuationDistanceModel::Inverse:
            return 1.0f / (1.0f + NormalizedDistance);

        case EAttenuationDistanceModel::LogReverse:
            return FMath::Max(0.0f,
                0.5f * FMath::Loge(1.0f + (1.0f - NormalizedDistance)));

        case EAttenuationDistanceModel::NaturalSound:
            // Attempt to model real-world sound falloff
            return FMath::Pow(10.0f, -NormalizedDistance * 0.1f);

        case EAttenuationDistanceModel::Custom:
            return Settings.CustomAttenuationCurve.GetRichCurve()->Eval(
                NormalizedDistance);
    }

    return 1.0f;
}
```

### 5.2 Spatialization Plugins

```cpp
// Spatialization plugin interface
class IAudioSpatialization
{
public:
    virtual ~IAudioSpatialization() = default;

    // Initialize plugin
    virtual void Initialize(const FSpatializationParams& Params) = 0;

    // Process spatialization
    virtual void ProcessAudio(
        const FAudioPluginSourceInputData& InputData,
        FAudioPluginSourceOutputData& OutputData) = 0;

    // Supported features
    virtual bool SupportsHRTF() const { return false; }
    virtual bool SupportsRoomEffects() const { return false; }
    virtual bool SupportsOcclusion() const { return false; }
};

// Built-in spatialization methods
enum class ESpatializationAlgorithm : uint8
{
    // Simple panning (stereo)
    EqualPower,

    // 3D audio with HRTF
    HRTF,

    // Plugin-based (Steam Audio, Oculus, etc.)
    Plugin
};

// HRTF processing
class FHRTFProcessor
{
public:
    void Initialize(int32 SampleRate, int32 BlockSize)
    {
        // Load HRTF database
        HRTFDatabase.Load(TEXT("/Engine/Audio/HRTF/DefaultHRTF"));

        // Initialize convolution buffers
        LeftIR.SetNumZeroed(HRTFIRLength);
        RightIR.SetNumZeroed(HRTFIRLength);
        ConvolutionState.SetNumZeroed(HRTFIRLength);
    }

    void Process(const float* MonoInput, int32 NumSamples,
                const FVector& SourceDirection,
                float* LeftOutput, float* RightOutput)
    {
        // Get HRTF pair for source direction
        float Azimuth = FMath::Atan2(SourceDirection.Y, SourceDirection.X);
        float Elevation = FMath::Asin(SourceDirection.Z);

        HRTFDatabase.GetHRTF(Azimuth, Elevation, LeftIR, RightIR);

        // Convolve with impulse responses
        ConvolvePartitioned(MonoInput, NumSamples, LeftIR, LeftOutput);
        ConvolvePartitioned(MonoInput, NumSamples, RightIR, RightOutput);
    }

private:
    FHRTFDatabase HRTFDatabase;
    TArray<float> LeftIR;
    TArray<float> RightIR;
    TArray<float> ConvolutionState;
    static constexpr int32 HRTFIRLength = 512;
};
```

### 5.3 Occlusion & Obstruction

```cpp
// Audio occlusion system
class FAudioOcclusion
{
public:
    // Trace for occlusion
    FOcclusionResult TraceOcclusion(
        const FVector& ListenerLocation,
        const FVector& SourceLocation,
        UWorld* World)
    {
        FOcclusionResult Result;

        FHitResult Hit;
        FCollisionQueryParams Params;
        Params.bTraceComplex = false;
        Params.bReturnPhysicalMaterial = true;

        if (World->LineTraceSingleByChannel(
            Hit, ListenerLocation, SourceLocation,
            ECC_Visibility, Params))
        {
            Result.bIsOccluded = true;
            Result.OcclusionDistance = Hit.Distance;

            // Get material-based attenuation
            if (UPhysicalMaterial* PhysMat = Hit.PhysMaterial.Get())
            {
                Result.OcclusionAmount = PhysMat->GetAudioOcclusion();
            }
            else
            {
                Result.OcclusionAmount = 0.5f;  // Default
            }
        }

        return Result;
    }

    // Apply occlusion filtering
    void ApplyOcclusionFilter(const FOcclusionResult& Occlusion,
                             FAudioSourceState& SourceState)
    {
        if (!Occlusion.bIsOccluded)
        {
            // Smoothly return to unoccluded state
            SourceState.CurrentOcclusion = FMath::FInterpTo(
                SourceState.CurrentOcclusion, 0.0f,
                DeltaTime, OcclusionInterpSpeed);
        }
        else
        {
            SourceState.CurrentOcclusion = FMath::FInterpTo(
                SourceState.CurrentOcclusion, Occlusion.OcclusionAmount,
                DeltaTime, OcclusionInterpSpeed);
        }

        // Calculate filter frequency
        float FilterFreq = FMath::Lerp(
            20000.0f,  // Unoccluded
            1000.0f,   // Fully occluded
            SourceState.CurrentOcclusion
        );

        SourceState.OcclusionFilter.SetFrequency(FilterFreq);
    }

private:
    float OcclusionInterpSpeed = 6.0f;  // Per second
};
```

### 5.4 Audio Volumes

```cpp
// Audio volume actor
UCLASS()
class AAudioVolume : public AVolume
{
    GENERATED_BODY()

public:
    // Reverb settings
    UPROPERTY(EditAnywhere, Category = "Reverb")
    FReverbSettings ReverbSettings;

    // Interior settings (ambient zone)
    UPROPERTY(EditAnywhere, Category = "Interior")
    FInteriorSettings InteriorSettings;

    // Priority (higher = override)
    UPROPERTY(EditAnywhere, Category = "Audio Volume")
    float Priority = 0.0f;

    // Submix send for sounds inside volume
    UPROPERTY(EditAnywhere, Category = "Submix")
    TObjectPtr<USoundSubmix> SubmixOverride;
};

// Interior settings
USTRUCT()
struct FInteriorSettings
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    bool bIsWorldSettings = false;

    UPROPERTY(EditAnywhere)
    float ExteriorVolume = 1.0f;

    UPROPERTY(EditAnywhere)
    float ExteriorTime = 0.5f;

    UPROPERTY(EditAnywhere)
    float ExteriorLPF = 20000.0f;

    UPROPERTY(EditAnywhere)
    float ExteriorLPFTime = 0.5f;

    UPROPERTY(EditAnywhere)
    float InteriorVolume = 1.0f;

    UPROPERTY(EditAnywhere)
    float InteriorTime = 0.5f;

    UPROPERTY(EditAnywhere)
    float InteriorLPF = 20000.0f;

    UPROPERTY(EditAnywhere)
    float InteriorLPFTime = 0.5f;
};
```

---

## 6. Submix System

### 6.1 Submix Architecture

```cpp
// Submix asset
UCLASS()
class USoundSubmixBase : public UObject
{
    GENERATED_BODY()

public:
    // Parent submix (routes output to parent)
    UPROPERTY(EditAnywhere, Category = "Submix")
    TObjectPtr<USoundSubmixBase> ParentSubmix;

    // Child submixes
    UPROPERTY(VisibleAnywhere, Category = "Submix")
    TArray<TObjectPtr<USoundSubmixBase>> ChildSubmixes;

    // Output volume
    UPROPERTY(EditAnywhere, Category = "Submix", meta = (ClampMin = "0.0"))
    float OutputVolume = 1.0f;

    // Wet/dry mix for effects
    UPROPERTY(EditAnywhere, Category = "Submix", meta = (ClampMin = "0.0", ClampMax = "1.0"))
    float WetLevel = 1.0f;

    UPROPERTY(EditAnywhere, Category = "Submix", meta = (ClampMin = "0.0", ClampMax = "1.0"))
    float DryLevel = 1.0f;
};

// Submix with effects
UCLASS()
class USoundSubmix : public USoundSubmixBase
{
    GENERATED_BODY()

public:
    // Submix effect chain
    UPROPERTY(EditAnywhere, Category = "Submix")
    TArray<TObjectPtr<USoundEffectSubmixPreset>> SubmixEffectChain;

    // Send to other submixes (reverb sends, etc.)
    UPROPERTY(EditAnywhere, Category = "Submix")
    TArray<FSoundSubmixSendInfo> SubmixSends;

    // Envelope follower (for visualization/sidechain)
    UPROPERTY(EditAnywhere, Category = "Analysis")
    bool bEnableEnvelopeFollower = false;

    UPROPERTY(EditAnywhere, Category = "Analysis")
    float EnvelopeFollowerAttackTime = 10.0f;  // ms

    UPROPERTY(EditAnywhere, Category = "Analysis")
    float EnvelopeFollowerReleaseTime = 100.0f;  // ms

    // Spectrum analysis
    UPROPERTY(EditAnywhere, Category = "Analysis")
    bool bEnableSpectrumAnalysis = false;

    UPROPERTY(EditAnywhere, Category = "Analysis")
    EFFTSize FFTSize = EFFTSize::DefaultSize;
};
```

### 6.2 Submix Graph Routing

```
Submix Routing Example:

                         ┌─────────────┐
                         │   Master    │
                         │   Submix    │
                         └──────▲──────┘
                                │
           ┌────────────────────┼────────────────────┐
           │                    │                    │
    ┌──────┴──────┐      ┌──────┴──────┐      ┌──────┴──────┐
    │    Music    │      │     SFX     │      │   Voice     │
    │   Submix    │      │   Submix    │      │   Submix    │
    └──────▲──────┘      └──────▲──────┘      └─────────────┘
           │                    │
    ┌──────┴──────┐      ┌──────┴──────┐
    │  Reverb     │◄─────│  Reverb     │
    │  Send       │ Send │   Send      │
    └─────────────┘      └─────────────┘
```

### 6.3 Submix Effects

```cpp
// Submix effect base class
UCLASS()
class USoundEffectSubmix : public USoundEffectBase
{
    GENERATED_BODY()

public:
    virtual void OnInit(const FSoundEffectSubmixInitData& InData) {}
    virtual void OnPresetChanged() {}

    virtual void ProcessAudio(const FSoundEffectSubmixInputData& InData,
                             FSoundEffectSubmixOutputData& OutData) = 0;
};

// Example: Submix EQ effect
UCLASS()
class USubmixEffectEQ : public USoundEffectSubmix
{
public:
    virtual void OnInit(const FSoundEffectSubmixInitData& InData) override
    {
        SampleRate = InData.SampleRate;
        NumChannels = InData.NumOutputChannels;

        // Initialize per-channel filters
        for (int32 Band = 0; Band < NumBands; ++Band)
        {
            Filters[Band].SetNumChannels(NumChannels);
            Filters[Band].SetSampleRate(SampleRate);
        }
    }

    virtual void ProcessAudio(const FSoundEffectSubmixInputData& InData,
                             FSoundEffectSubmixOutputData& OutData) override
    {
        // Copy input to output
        FMemory::Memcpy(OutData.AudioBuffer->GetData(),
                       InData.AudioBuffer->GetData(),
                       InData.NumFrames * NumChannels * sizeof(float));

        // Apply each EQ band
        for (int32 Band = 0; Band < NumBands; ++Band)
        {
            if (BandSettings[Band].bEnabled)
            {
                Filters[Band].ProcessAudio(OutData.AudioBuffer->GetData(),
                                          InData.NumFrames,
                                          NumChannels);
            }
        }
    }

private:
    static constexpr int32 NumBands = 8;
    FBiquadFilter Filters[NumBands];
    FEQBandSettings BandSettings[NumBands];
    float SampleRate;
    int32 NumChannels;
};
```

### 6.4 Submix Recording

```cpp
// Record submix output to file
class FSubmixRecorder
{
public:
    void StartRecording(USoundSubmix* Submix, const FString& FilePath)
    {
        TargetSubmix = Submix;
        OutputPath = FilePath;
        bIsRecording = true;

        // Create wave writer
        WaveWriter = MakeUnique<FAudioFileWriter>();
        WaveWriter->Open(FilePath, SampleRate, NumChannels);

        // Register callback
        Submix->AddOnSubmixBufferListener(
            FOnSubmixBufferListener::CreateRaw(
                this, &FSubmixRecorder::OnSubmixBuffer));
    }

    void StopRecording()
    {
        bIsRecording = false;
        TargetSubmix->RemoveOnSubmixBufferListener();
        WaveWriter->Close();
    }

private:
    void OnSubmixBuffer(const float* AudioData, int32 NumFrames,
                       int32 NumChannels)
    {
        if (bIsRecording)
        {
            WaveWriter->Write(AudioData, NumFrames * NumChannels);
        }
    }

    USoundSubmix* TargetSubmix;
    FString OutputPath;
    TUniquePtr<FAudioFileWriter> WaveWriter;
    float SampleRate = 48000.0f;
    int32 NumChannels = 2;
    bool bIsRecording = false;
};
```

---

## 7. Quartz Quantization

### 7.1 Quartz System Overview

Quartz is UE5's musical timing system for sample-accurate audio synchronization.

```cpp
// Quartz clock
UCLASS()
class UQuartzClockHandle : public UObject
{
    GENERATED_BODY()

public:
    // Start the clock
    UFUNCTION(BlueprintCallable, Category = "Quartz")
    void StartClock(UWorld* World, const FQuartzClockSettings& Settings);

    // Set tempo
    UFUNCTION(BlueprintCallable, Category = "Quartz")
    void SetBeatsPerMinute(float BPM);

    // Get current musical time
    UFUNCTION(BlueprintPure, Category = "Quartz")
    FQuartzTransportTimeStamp GetCurrentTimestamp() const;

    // Subscribe to quantization events
    UFUNCTION(BlueprintCallable, Category = "Quartz")
    void SubscribeToQuantizationEvent(
        EQuartzCommandQuantization QuantizationType,
        const FOnQuartzCommandEvent& Delegate);

    // Play sound quantized
    UFUNCTION(BlueprintCallable, Category = "Quartz")
    void PlaySoundQuantized(
        UObject* WorldContextObject,
        USoundBase* Sound,
        EQuartzCommandQuantization Quantization,
        const FOnQuartzCommandEvent& OnCommandEvent);
};

// Quantization types
UENUM()
enum class EQuartzCommandQuantization : uint8
{
    Bar,
    Beat,
    ThirtySecondNote,
    SixteenthNote,
    EighthNote,
    QuarterNote,
    HalfNote,
    WholeNote,
    DottedSixteenthNote,
    DottedEighthNote,
    DottedQuarterNote,
    DottedHalfNote,
    SixteenthNoteTriplet,
    EighthNoteTriplet,
    QuarterNoteTriplet,
    HalfNoteTriplet,
    None  // Immediate
};
```

### 7.2 Quartz Clock Implementation

```cpp
// Internal Quartz clock
class FQuartzClock
{
public:
    FQuartzClock(const FQuartzClockSettings& Settings)
        : BeatsPerMinute(Settings.BeatsPerMinute)
        , BeatsPerBar(Settings.TimeSignatureNumerator)
        , BeatUnit(Settings.TimeSignatureDenominator)
        , SampleRate(Settings.SampleRate)
    {
        RecalculateTiming();
    }

    // Advance clock by samples
    void Tick(int32 NumSamples)
    {
        SampleCounter += NumSamples;

        while (SampleCounter >= SamplesPerBeat)
        {
            SampleCounter -= SamplesPerBeat;
            BeatCounter++;

            // Fire beat event
            OnBeat.Broadcast(CurrentBar, CurrentBeat);

            if (BeatCounter >= BeatsPerBar)
            {
                BeatCounter = 0;
                BarCounter++;

                // Fire bar event
                OnBar.Broadcast(CurrentBar);
            }
        }

        // Process pending quantized commands
        ProcessQuantizedCommands();
    }

    // Schedule command at quantization boundary
    void ScheduleCommand(TUniquePtr<FQuartzCommand> Command,
                        EQuartzCommandQuantization Quantization)
    {
        int64 TargetSample = GetNextQuantizationBoundary(Quantization);
        PendingCommands.HeapPush({TargetSample, MoveTemp(Command)});
    }

private:
    void RecalculateTiming()
    {
        // Samples per beat = (60 / BPM) * SampleRate
        SamplesPerBeat = (60.0 / BeatsPerMinute) * SampleRate;
        SamplesPerBar = SamplesPerBeat * BeatsPerBar;

        // Sub-divisions
        SamplesPerSixteenth = SamplesPerBeat / 4;
        SamplesPerEighth = SamplesPerBeat / 2;
    }

    int64 GetNextQuantizationBoundary(EQuartzCommandQuantization Quantization)
    {
        int64 CurrentSample = GetCurrentSample();
        int64 Division;

        switch (Quantization)
        {
            case EQuartzCommandQuantization::Bar:
                Division = SamplesPerBar;
                break;
            case EQuartzCommandQuantization::Beat:
            case EQuartzCommandQuantization::QuarterNote:
                Division = SamplesPerBeat;
                break;
            case EQuartzCommandQuantization::EighthNote:
                Division = SamplesPerEighth;
                break;
            case EQuartzCommandQuantization::SixteenthNote:
                Division = SamplesPerSixteenth;
                break;
            // ... other cases
            default:
                return CurrentSample;  // Immediate
        }

        return ((CurrentSample / Division) + 1) * Division;
    }

    float BeatsPerMinute;
    int32 BeatsPerBar;
    int32 BeatUnit;
    float SampleRate;

    int64 SamplesPerBeat;
    int64 SamplesPerBar;
    int64 SamplesPerSixteenth;
    int64 SamplesPerEighth;

    int64 SampleCounter = 0;
    int32 BeatCounter = 0;
    int32 BarCounter = 0;

    TArray<FQuantizedCommand> PendingCommands;

    FOnQuartzBeat OnBeat;
    FOnQuartzBar OnBar;
};
```

### 7.3 Musical Synchronization

```cpp
// Example: Synchronized music system
class FMusicManager
{
public:
    void SetupMusicClock(UWorld* World)
    {
        // Create Quartz clock
        FQuartzClockSettings Settings;
        Settings.BeatsPerMinute = 120.0f;
        Settings.TimeSignatureNumerator = 4;
        Settings.TimeSignatureDenominator = 4;

        Clock = UQuartzSubsystem::Get(World)->CreateClock(
            TEXT("MusicClock"), Settings);

        // Subscribe to beat/bar events
        Clock->SubscribeToQuantizationEvent(
            EQuartzCommandQuantization::Beat,
            FOnQuartzCommandEvent::CreateRaw(this, &FMusicManager::OnBeat));

        Clock->SubscribeToQuantizationEvent(
            EQuartzCommandQuantization::Bar,
            FOnQuartzCommandEvent::CreateRaw(this, &FMusicManager::OnBar));
    }

    // Play stem quantized to next bar
    void QueueStem(USoundBase* Stem)
    {
        Clock->PlaySoundQuantized(
            World,
            Stem,
            EQuartzCommandQuantization::Bar,
            FOnQuartzCommandEvent::CreateLambda([](EQuartzCommandResult Result)
            {
                UE_LOG(LogAudio, Log, TEXT("Stem started"));
            })
        );
    }

    // Transition to new section
    void TransitionToSection(int32 SectionIndex)
    {
        // Schedule fade out of current stems
        for (auto& Stem : CurrentStems)
        {
            Clock->FadeOutAndStop(Stem, 2.0f, EQuartzCommandQuantization::Bar);
        }

        // Queue new stems
        for (auto& NewStem : Sections[SectionIndex].Stems)
        {
            QueueStem(NewStem);
        }
    }

private:
    void OnBeat(EQuartzCommandResult Result)
    {
        // Trigger beat-synced gameplay events
        OnMusicBeat.Broadcast();
    }

    void OnBar(EQuartzCommandResult Result)
    {
        BarCounter++;

        // Check for section transitions
        if (PendingTransition && BarCounter >= TransitionBar)
        {
            ExecuteTransition();
        }
    }

    UQuartzClockHandle* Clock;
    TArray<FAudioComponent*> CurrentStems;
    int32 BarCounter = 0;
};
```

---

## 8. Source Effects & DSP

### 8.1 Source Effect System

Source effects process individual sound sources before submix routing.

```cpp
// Source effect base
UCLASS()
class USoundEffectSourcePreset : public USoundEffectPreset
{
    GENERATED_BODY()

public:
    virtual void OnInit(const FSoundEffectSourceInitData& InData) {}
    virtual void OnPresetChanged() {}

    virtual void ProcessAudio(const FSoundEffectSourceInputData& InData,
                             float* OutAudioBufferData) = 0;
};

// Example: Pitch shifter source effect
UCLASS()
class USourceEffectPitchShifter : public USoundEffectSource
{
public:
    virtual void OnInit(const FSoundEffectSourceInitData& InData) override
    {
        SampleRate = InData.SampleRate;
        NumChannels = InData.NumSourceChannels;

        // Initialize granular pitch shifter
        GranularShifter.Initialize(SampleRate, GrainSize, NumGrains);
    }

    virtual void ProcessAudio(const FSoundEffectSourceInputData& InData,
                             float* OutAudioBufferData) override
    {
        // Get current settings
        float Shift = Settings->PitchShiftSemitones;
        float GrainPitch = FMath::Pow(2.0f, Shift / 12.0f);

        GranularShifter.SetPitchRatio(GrainPitch);
        GranularShifter.Process(InData.InputSourceEffectBufferPtr,
                               OutAudioBufferData,
                               InData.NumSamples,
                               NumChannels);
    }

private:
    FGranularPitchShifter GranularShifter;
    float SampleRate;
    int32 NumChannels;
    static constexpr int32 GrainSize = 64;  // ms
    static constexpr int32 NumGrains = 4;
};
```

### 8.2 Built-in Source Effects

```cpp
// Available source effects in UE5
namespace SourceEffects
{
    // Dynamics
    class FSourceEffectChorus;         // Multi-voice chorus
    class FSourceEffectBitCrusher;     // Lo-fi effect
    class FSourceEffectDynamicsProcessor;  // Compressor/limiter/gate
    class FSourceEffectEnvelopeFollower;   // Envelope detection
    class FSourceEffectEQ;             // Parametric EQ
    class FSourceEffectFilter;         // LP/HP/BP filter
    class FSourceEffectFoldback;       // Wavefolder distortion
    class FSourceEffectMidSideSpreader;// Stereo width
    class FSourceEffectMotionFilter;   // Modulated filter
    class FSourceEffectPanner;         // Stereo panning
    class FSourceEffectPhaser;         // Phaser effect
    class FSourceEffectRingModulator;  // Ring modulation
    class FSourceEffectSimpleDelay;    // Basic delay
    class FSourceEffectStereoDelay;    // Ping-pong delay
    class FSourceEffectWaveShaper;     // Distortion/saturation
}
```

### 8.3 Source Effect Chain

```cpp
// Source effect chain configuration
USTRUCT()
struct FSourceEffectChainEntry
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    TObjectPtr<USoundEffectSourcePreset> Preset;

    UPROPERTY(EditAnywhere)
    bool bBypass = false;
};

UCLASS()
class USoundEffectSourcePresetChain : public UObject
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, Category = "SourceEffect")
    TArray<FSourceEffectChainEntry> Chain;

    // Play sound through this effect chain
    void ApplyToSound(UAudioComponent* AudioComponent)
    {
        AudioComponent->SetSourceEffectChain(this);
    }
};
```

---

## 9. Audio Components

### 9.1 Audio Component

```cpp
// Primary audio playback component
UCLASS()
class UAudioComponent : public USceneComponent
{
    GENERATED_BODY()

public:
    // Sound to play
    UPROPERTY(EditAnywhere, Category = "Sound")
    TObjectPtr<USoundBase> Sound;

    // Playback control
    UFUNCTION(BlueprintCallable, Category = "Audio")
    void Play(float StartTime = 0.0f);

    UFUNCTION(BlueprintCallable, Category = "Audio")
    void Stop();

    UFUNCTION(BlueprintCallable, Category = "Audio")
    void SetPaused(bool bPause);

    UFUNCTION(BlueprintCallable, Category = "Audio")
    void FadeIn(float FadeInDuration, float FadeVolumeLevel = 1.0f);

    UFUNCTION(BlueprintCallable, Category = "Audio")
    void FadeOut(float FadeOutDuration, float FadeVolumeLevel = 0.0f);

    // Volume/pitch control
    UPROPERTY(EditAnywhere, Category = "Sound", meta = (ClampMin = "0.0"))
    float VolumeMultiplier = 1.0f;

    UPROPERTY(EditAnywhere, Category = "Sound", meta = (ClampMin = "0.1", ClampMax = "4.0"))
    float PitchMultiplier = 1.0f;

    // Attenuation override
    UPROPERTY(EditAnywhere, Category = "Attenuation")
    TObjectPtr<USoundAttenuation> AttenuationSettings;

    // Submix override
    UPROPERTY(EditAnywhere, Category = "Submix")
    TObjectPtr<USoundSubmix> OverrideSubmix;

    // Source effect chain
    UPROPERTY(EditAnywhere, Category = "Effects")
    TObjectPtr<USoundEffectSourcePresetChain> SourceEffectChain;

    // Events
    UPROPERTY(BlueprintAssignable, Category = "Audio|Events")
    FOnAudioFinished OnAudioFinished;

    UPROPERTY(BlueprintAssignable, Category = "Audio|Events")
    FOnAudioPlaybackPercent OnAudioPlaybackPercent;
};
```

### 9.2 Ambient Sound Actor

```cpp
// Ambient sound placement actor
UCLASS()
class AAmbientSound : public AActor
{
    GENERATED_BODY()

public:
    AAmbientSound()
    {
        AudioComponent = CreateDefaultSubobject<UAudioComponent>(
            TEXT("AudioComponent"));
        AudioComponent->bAutoActivate = true;
        AudioComponent->bStopWhenOwnerDestroyed = true;

        SetRootComponent(AudioComponent);
    }

    UPROPERTY(VisibleAnywhere, Category = "Audio")
    TObjectPtr<UAudioComponent> AudioComponent;
};
```

### 9.3 Synth Component

```cpp
// Procedural synthesis component
UCLASS()
class USynthComponent : public USceneComponent
{
    GENERATED_BODY()

public:
    // Start synthesis
    UFUNCTION(BlueprintCallable, Category = "Synth")
    void Start();

    UFUNCTION(BlueprintCallable, Category = "Synth")
    void Stop();

    // Override to generate audio
    virtual int32 OnGenerateAudio(float* OutAudio, int32 NumSamples);

    // Synth settings
    UPROPERTY(EditAnywhere, Category = "Synth")
    int32 NumChannels = 2;

    UPROPERTY(EditAnywhere, Category = "Synth")
    float VolumeMultiplier = 1.0f;
};
```

---

## 10. Synthesis Framework

### 10.1 Modular Synthesizer

```cpp
// UE5 includes a modular synthesis framework
namespace Audio
{
    // Oscillator
    class FOsc
    {
    public:
        enum class EType
        {
            Sine,
            Saw,
            Square,
            Triangle,
            Noise
        };

        void Init(float InSampleRate, int32 InVoiceId = 0);
        void SetType(EType InType);
        void SetFrequency(float InFrequency);
        void SetPulseWidth(float InPulseWidth);  // For square wave

        void Generate(float* OutBuffer, int32 NumSamples);

    private:
        float SampleRate;
        EType Type = EType::Sine;
        float Frequency = 440.0f;
        float Phase = 0.0f;
        float PulseWidth = 0.5f;
    };

    // Filter
    class FLadderFilter
    {
    public:
        enum class EMode
        {
            LPF12,
            LPF24,
            HPF12,
            HPF24,
            BPF12,
            BPF24
        };

        void Init(float InSampleRate);
        void SetMode(EMode InMode);
        void SetCutoffFrequency(float InFrequency);
        void SetResonance(float InResonance);  // 0.0 - 1.0

        void ProcessAudio(float* InOutBuffer, int32 NumSamples);

    private:
        float SampleRate;
        EMode Mode = EMode::LPF24;
        float Cutoff = 1000.0f;
        float Resonance = 0.0f;
        float Stage[4] = {0};  // 4-pole ladder
    };

    // Envelope
    class FEnvelope
    {
    public:
        void Init(float InSampleRate);

        void SetAttack(float InAttackMs);
        void SetDecay(float InDecayMs);
        void SetSustain(float InSustainLevel);
        void SetRelease(float InReleaseMs);

        void NoteOn();
        void NoteOff();

        float Generate();
        bool IsDone() const;

    private:
        enum class EStage { Idle, Attack, Decay, Sustain, Release };

        float SampleRate;
        EStage Stage = EStage::Idle;
        float CurrentValue = 0.0f;
        float AttackRate;
        float DecayRate;
        float SustainLevel;
        float ReleaseRate;
    };

    // LFO
    class FLFO
    {
    public:
        void Init(float InSampleRate);
        void SetFrequency(float InFrequency);
        void SetType(FOsc::EType InType);
        void SetDepth(float InDepth);

        float Generate();

    private:
        FOsc Oscillator;
        float Depth = 1.0f;
    };
}
```

### 10.2 Modular Synth Component

```cpp
// Blueprint-accessible modular synth
UCLASS()
class UModularSynthComponent : public USynthComponent
{
    GENERATED_BODY()

public:
    // Oscillators
    UPROPERTY(EditAnywhere, Category = "Oscillators")
    int32 NumOscillators = 3;

    UPROPERTY(EditAnywhere, Category = "Oscillators")
    TArray<FOscillatorSettings> OscillatorSettings;

    // Filter
    UPROPERTY(EditAnywhere, Category = "Filter")
    FFilterSettings FilterSettings;

    // Envelope
    UPROPERTY(EditAnywhere, Category = "Envelope")
    FADSRSettings AmpEnvelope;

    UPROPERTY(EditAnywhere, Category = "Envelope")
    FADSRSettings FilterEnvelope;

    // LFOs
    UPROPERTY(EditAnywhere, Category = "LFO")
    TArray<FLFOSettings> LFOSettings;

    // Note control
    UFUNCTION(BlueprintCallable, Category = "Synth")
    void NoteOn(int32 MidiNote, int32 Velocity);

    UFUNCTION(BlueprintCallable, Category = "Synth")
    void NoteOff(int32 MidiNote);

    virtual int32 OnGenerateAudio(float* OutAudio, int32 NumSamples) override;

private:
    TArray<FVoice> Voices;
    Audio::FLadderFilter Filter;
};
```

---

## 11. Convolution Reverb

### 11.1 Convolution Reverb System

```cpp
// Convolution reverb submix effect
UCLASS()
class USubmixEffectConvolutionReverbPreset : public USoundEffectSubmixPreset
{
    GENERATED_BODY()

public:
    // Impulse response asset
    UPROPERTY(EditAnywhere, Category = "Convolution Reverb")
    TObjectPtr<UAudioImpulseResponse> ImpulseResponse;

    // Wet/Dry mix
    UPROPERTY(EditAnywhere, Category = "Convolution Reverb",
              meta = (ClampMin = "0.0", ClampMax = "1.0"))
    float WetLevel = 0.5f;

    UPROPERTY(EditAnywhere, Category = "Convolution Reverb",
              meta = (ClampMin = "0.0", ClampMax = "1.0"))
    float DryLevel = 1.0f;

    // Pre-delay
    UPROPERTY(EditAnywhere, Category = "Convolution Reverb",
              meta = (ClampMin = "0.0", ClampMax = "500.0"))
    float PreDelayMs = 0.0f;

    // Enable hardware acceleration
    UPROPERTY(EditAnywhere, Category = "Convolution Reverb")
    bool bEnableHardwareAcceleration = true;
};

// Impulse response asset
UCLASS()
class UAudioImpulseResponse : public UObject
{
    GENERATED_BODY()

public:
    // IR samples
    UPROPERTY()
    TArray<float> ImpulseResponse;

    // IR properties
    UPROPERTY(EditAnywhere)
    int32 NumChannels = 2;

    UPROPERTY(EditAnywhere)
    int32 SampleRate = 48000;

    // True stereo (4-channel: LL, LR, RL, RR)
    UPROPERTY(EditAnywhere)
    bool bTrueStereo = false;

    // Normalization
    UPROPERTY(EditAnywhere)
    bool bNormalize = true;
};
```

### 11.2 Partitioned Convolution Implementation

```cpp
// Efficient convolution using overlap-add with FFT
class FConvolutionReverb
{
public:
    void Initialize(const TArray<float>& IR, int32 BlockSize,
                   float InSampleRate)
    {
        SampleRate = InSampleRate;

        // Partition IR into blocks
        const int32 FFTSize = BlockSize * 2;
        const int32 NumPartitions = (IR.Num() + BlockSize - 1) / BlockSize;

        // Pre-compute FFT of each IR partition
        IRPartitionsFFT.SetNum(NumPartitions);
        for (int32 p = 0; p < NumPartitions; ++p)
        {
            TArray<float> Partition;
            Partition.SetNumZeroed(FFTSize);

            int32 Start = p * BlockSize;
            int32 Count = FMath::Min(BlockSize, IR.Num() - Start);
            FMemory::Memcpy(Partition.GetData(), &IR[Start],
                          Count * sizeof(float));

            FFT.Forward(Partition.GetData(), IRPartitionsFFT[p].GetData(),
                       FFTSize);
        }

        // Initialize processing buffers
        InputHistory.SetNumZeroed(NumPartitions);
        for (auto& Buf : InputHistory)
        {
            Buf.SetNumZeroed(FFTSize);
        }

        AccumulationBuffer.SetNumZeroed(FFTSize);
        OverlapBuffer.SetNumZeroed(BlockSize);
    }

    void Process(const float* Input, float* Output, int32 NumSamples)
    {
        const int32 FFTSize = NumSamples * 2;

        // Shift input history
        for (int32 p = InputHistory.Num() - 1; p > 0; --p)
        {
            InputHistory[p] = InputHistory[p - 1];
        }

        // FFT of new input block
        TArray<float> PaddedInput;
        PaddedInput.SetNumZeroed(FFTSize);
        FMemory::Memcpy(PaddedInput.GetData(), Input,
                       NumSamples * sizeof(float));
        FFT.Forward(PaddedInput.GetData(), InputHistory[0].GetData(), FFTSize);

        // Clear accumulation buffer
        FMemory::Memzero(AccumulationBuffer.GetData(),
                        FFTSize * sizeof(FComplexFloat));

        // Multiply and accumulate all partitions
        for (int32 p = 0; p < IRPartitionsFFT.Num(); ++p)
        {
            for (int32 i = 0; i < FFTSize; ++i)
            {
                AccumulationBuffer[i] += InputHistory[p][i] *
                                        IRPartitionsFFT[p][i];
            }
        }

        // IFFT
        TArray<float> OutputBlock;
        OutputBlock.SetNumZeroed(FFTSize);
        FFT.Inverse(AccumulationBuffer.GetData(), OutputBlock.GetData(),
                   FFTSize);

        // Overlap-add
        for (int32 i = 0; i < NumSamples; ++i)
        {
            Output[i] = OutputBlock[i] + OverlapBuffer[i];
            OverlapBuffer[i] = OutputBlock[i + NumSamples];
        }
    }

private:
    FFT FFT;
    float SampleRate;
    TArray<TArray<FComplexFloat>> IRPartitionsFFT;
    TArray<TArray<FComplexFloat>> InputHistory;
    TArray<FComplexFloat> AccumulationBuffer;
    TArray<float> OverlapBuffer;
};
```

---

## 12. Audio Modulation System

### 12.1 Modulation Plugin Architecture

```cpp
// Audio modulation plugin interface
class IAudioModulation
{
public:
    virtual ~IAudioModulation() = default;

    // Initialize modulation system
    virtual void Initialize(const FAudioModulationInitParams& Params) = 0;

    // Process modulation (called each audio block)
    virtual void ProcessModulation(float DeltaTime) = 0;

    // Get modulated parameter value
    virtual float GetModulatedValue(const FName& ParameterName,
                                   float BaseValue) const = 0;
};

// Modulation destination
UENUM()
enum class EModulationDestination : uint8
{
    Volume,
    Pitch,
    LowPassFilterFrequency,
    HighPassFilterFrequency,
    PanPosition,
    ReverbSend,
    ChorusMix,
    Custom
};

// Modulation source types
UENUM()
enum class EModulationSourceType : uint8
{
    LFO,
    Envelope,
    Random,
    ControlBus,
    GameParameter
};
```

### 12.2 Control Bus System

```cpp
// Control bus for global parameter control
UCLASS()
class USoundControlBus : public UObject
{
    GENERATED_BODY()

public:
    // Bus name
    UPROPERTY(EditAnywhere, Category = "Control Bus")
    FName BusName;

    // Default value
    UPROPERTY(EditAnywhere, Category = "Control Bus",
              meta = (ClampMin = "0.0", ClampMax = "1.0"))
    float DefaultValue = 1.0f;

    // Current value (runtime)
    float GetValue() const { return CurrentValue; }

    // Set value (with optional fade)
    void SetValue(float NewValue, float FadeTime = 0.0f);

    // Modulation parameters connected to this bus
    UPROPERTY(EditAnywhere, Category = "Control Bus")
    TArray<FModulationDestinationSettings> Destinations;

private:
    float CurrentValue = 1.0f;
    float TargetValue = 1.0f;
    float FadeTimeRemaining = 0.0f;
};

// Control bus mix asset
UCLASS()
class USoundControlBusMix : public UObject
{
    GENERATED_BODY()

public:
    // Bus stages (sets of parameter values)
    UPROPERTY(EditAnywhere, Category = "Control Bus Mix")
    TArray<FSoundControlBusMixStage> Stages;

    // Activate mix stage
    UFUNCTION(BlueprintCallable, Category = "Audio|Control Bus")
    void ActivateStage(int32 StageIndex, float FadeTime = 0.0f);

    // Deactivate mix
    UFUNCTION(BlueprintCallable, Category = "Audio|Control Bus")
    void Deactivate(float FadeTime = 0.0f);
};
```

### 12.3 Parameter Modulation

```cpp
// Modulation routing
struct FModulationRouting
{
    // Source
    EModulationSourceType SourceType;
    TWeakObjectPtr<UObject> Source;  // LFO, Envelope, Bus, etc.

    // Destination
    EModulationDestination Destination;
    FName CustomDestinationName;

    // Modulation amount
    float Depth = 1.0f;

    // Modulation mode
    enum class EMode { Add, Multiply, Replace } Mode = EMode::Multiply;
};

// Apply modulation to sound
class FAudioModulator
{
public:
    void AddRouting(const FModulationRouting& Routing)
    {
        Routings.Add(Routing);
    }

    float GetModulatedParameter(EModulationDestination Dest,
                               float BaseValue) const
    {
        float ModulatedValue = BaseValue;

        for (const auto& Routing : Routings)
        {
            if (Routing.Destination == Dest)
            {
                float SourceValue = GetSourceValue(Routing);

                switch (Routing.Mode)
                {
                    case FModulationRouting::EMode::Add:
                        ModulatedValue += SourceValue * Routing.Depth;
                        break;
                    case FModulationRouting::EMode::Multiply:
                        ModulatedValue *= 1.0f + (SourceValue - 1.0f) * Routing.Depth;
                        break;
                    case FModulationRouting::EMode::Replace:
                        ModulatedValue = FMath::Lerp(BaseValue, SourceValue,
                                                    Routing.Depth);
                        break;
                }
            }
        }

        return ModulatedValue;
    }

private:
    TArray<FModulationRouting> Routings;
};
```

---

## 13. Soundscape System

### 13.1 Soundscape Overview

UE5's Soundscape system provides tools for creating immersive ambient environments.

```cpp
// Soundscape palette - collection of sounds
UCLASS()
class USoundscapePalette : public UObject
{
    GENERATED_BODY()

public:
    // Sound entries
    UPROPERTY(EditAnywhere, Category = "Soundscape")
    TArray<FSoundscapeColor> Colors;

    // Global settings
    UPROPERTY(EditAnywhere, Category = "Soundscape")
    float MasterVolume = 1.0f;

    UPROPERTY(EditAnywhere, Category = "Soundscape")
    float FadeInTime = 2.0f;

    UPROPERTY(EditAnywhere, Category = "Soundscape")
    float FadeOutTime = 2.0f;
};

// Soundscape color - individual sound element
USTRUCT()
struct FSoundscapeColor
{
    GENERATED_BODY()

    // Sound to play
    UPROPERTY(EditAnywhere)
    TObjectPtr<USoundBase> Sound;

    // Volume range
    UPROPERTY(EditAnywhere)
    FFloatInterval VolumeRange = {0.8f, 1.0f};

    // Pitch range
    UPROPERTY(EditAnywhere)
    FFloatInterval PitchRange = {0.95f, 1.05f};

    // Spawn timing
    UPROPERTY(EditAnywhere)
    FFloatInterval SpawnInterval = {5.0f, 15.0f};

    // Maximum concurrent instances
    UPROPERTY(EditAnywhere)
    int32 MaxInstances = 3;

    // 3D spawning
    UPROPERTY(EditAnywhere)
    bool bEnable3DSpawning = true;

    UPROPERTY(EditAnywhere)
    FFloatInterval SpawnDistance = {500.0f, 3000.0f};

    UPROPERTY(EditAnywhere)
    FFloatInterval SpawnHeight = {-100.0f, 500.0f};
};
```

### 13.2 Soundscape Subsystem

```cpp
// Soundscape management
UCLASS()
class USoundscapeSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()

public:
    // Activate soundscape palette
    UFUNCTION(BlueprintCallable, Category = "Soundscape")
    void SetActiveSoundscape(USoundscapePalette* Palette);

    // Blend between palettes
    UFUNCTION(BlueprintCallable, Category = "Soundscape")
    void BlendToSoundscape(USoundscapePalette* NewPalette,
                          float BlendTime);

    // Update listener location (call from player controller)
    void UpdateListenerLocation(const FVector& Location,
                               const FRotator& Rotation);

private:
    virtual void Tick(float DeltaTime) override;

    void SpawnSoundscapeElement(const FSoundscapeColor& Color);
    FVector GetSpawnLocation(const FSoundscapeColor& Color) const;

    USoundscapePalette* ActivePalette;
    USoundscapePalette* PreviousPalette;
    float BlendAlpha = 1.0f;
    float BlendTime = 0.0f;

    FVector ListenerLocation;
    FRotator ListenerRotation;

    TArray<FAudioComponent*> ActiveSounds;
};
```

---

## 14. Platform Audio

### 14.1 Platform-Specific Implementation

```cpp
// Platform audio abstraction
class IAudioPlatform
{
public:
    virtual ~IAudioPlatform() = default;

    // Initialize audio device
    virtual bool Initialize(const FAudioPlatformSettings& Settings) = 0;

    // Get available devices
    virtual TArray<FAudioDeviceInfo> GetAvailableDevices() const = 0;

    // Open audio stream
    virtual bool OpenStream(int32 DeviceIndex,
                           const FAudioStreamSettings& Settings,
                           FAudioCallback Callback) = 0;

    // Start/stop stream
    virtual void StartStream() = 0;
    virtual void StopStream() = 0;

    // Get stream info
    virtual FAudioStreamInfo GetStreamInfo() const = 0;
};

// Platform implementations
#if PLATFORM_WINDOWS
class FWindowsAudioPlatform : public IAudioPlatform
{
    // XAudio2 implementation
};
#elif PLATFORM_MAC
class FMacAudioPlatform : public IAudioPlatform
{
    // CoreAudio implementation
};
#elif PLATFORM_LINUX
class FLinuxAudioPlatform : public IAudioPlatform
{
    // PulseAudio/ALSA implementation
};
#elif PLATFORM_PS5
class FPS5AudioPlatform : public IAudioPlatform
{
    // PlayStation 5 audio implementation
    // Uses Tempest 3D Audio Engine
};
#elif PLATFORM_XSX
class FXboxSeriesAudioPlatform : public IAudioPlatform
{
    // Xbox Series X|S audio implementation
    // Uses Project Acoustics integration
};
#elif PLATFORM_SWITCH
class FSwitchAudioPlatform : public IAudioPlatform
{
    // Nintendo Switch audio implementation
};
#endif
```

### 14.2 Audio Settings

```cpp
// Audio quality settings
UCLASS()
class UAudioSettings : public UDeveloperSettings
{
    GENERATED_BODY()

public:
    // Default sample rate
    UPROPERTY(config, EditAnywhere, Category = "Audio")
    int32 DefaultSampleRate = 48000;

    // Quality presets
    UPROPERTY(config, EditAnywhere, Category = "Quality")
    TMap<FName, FAudioQualitySettings> QualitySettings;

    // Voice management
    UPROPERTY(config, EditAnywhere, Category = "Voice Management")
    int32 MaxVoices = 128;

    UPROPERTY(config, EditAnywhere, Category = "Voice Management")
    int32 DefaultMaxConcurrentStreams = 16;

    // Spatialization
    UPROPERTY(config, EditAnywhere, Category = "Spatialization")
    TSubclassOf<USpatializationPluginSourceSettingsBase>
        DefaultSpatializationPluginSettings;

    // Default attenuation
    UPROPERTY(config, EditAnywhere, Category = "Attenuation")
    TObjectPtr<USoundAttenuation> DefaultSoundAttenuation;

    // Default concurrency
    UPROPERTY(config, EditAnywhere, Category = "Concurrency")
    TObjectPtr<USoundConcurrency> DefaultSoundConcurrency;

    // Master submix
    UPROPERTY(config, EditAnywhere, Category = "Submix")
    TObjectPtr<USoundSubmix> MasterSubmix;
};

// Quality settings per platform
USTRUCT()
struct FAudioQualitySettings
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    int32 MaxChannels = 32;

    UPROPERTY(EditAnywhere)
    int32 SampleRate = 48000;

    UPROPERTY(EditAnywhere)
    int32 CallbackBufferFrameSize = 1024;

    UPROPERTY(EditAnywhere)
    int32 NumBuffers = 2;

    UPROPERTY(EditAnywhere)
    float ResampleQuality = 1.0f;  // 0-1
};
```

---

## 15. Memory Management

### 15.1 Audio Memory System

```cpp
// Audio memory allocation
class FAudioMemoryManager
{
public:
    // Memory pools
    struct FMemoryPool
    {
        TArray<uint8> Memory;
        int32 BlockSize;
        TBitArray<> AllocationMap;
    };

    // Initialize with budget
    void Initialize(int32 TotalBudgetMB)
    {
        TotalBudget = TotalBudgetMB * 1024 * 1024;

        // Create pools for common sizes
        CreatePool(256, 1024);      // Small (sound cue data)
        CreatePool(4096, 512);      // Medium (short samples)
        CreatePool(65536, 128);     // Large (streaming buffers)
        CreatePool(1048576, 16);    // XL (impulse responses)
    }

    // Allocate from pool
    void* Allocate(int32 Size)
    {
        // Find best-fit pool
        for (auto& Pool : Pools)
        {
            if (Pool.BlockSize >= Size)
            {
                int32 FreeBlock = Pool.AllocationMap.FindFirstZero();
                if (FreeBlock != INDEX_NONE)
                {
                    Pool.AllocationMap[FreeBlock] = true;
                    CurrentUsage += Pool.BlockSize;
                    return &Pool.Memory[FreeBlock * Pool.BlockSize];
                }
            }
        }

        // Fallback to heap
        return FMemory::Malloc(Size);
    }

    // Free to pool
    void Free(void* Ptr)
    {
        for (auto& Pool : Pools)
        {
            intptr_t Offset = (uint8*)Ptr - Pool.Memory.GetData();
            if (Offset >= 0 && Offset < Pool.Memory.Num())
            {
                int32 Block = Offset / Pool.BlockSize;
                Pool.AllocationMap[Block] = false;
                CurrentUsage -= Pool.BlockSize;
                return;
            }
        }

        // Not in pool, free from heap
        FMemory::Free(Ptr);
    }

    // Stats
    int32 GetCurrentUsage() const { return CurrentUsage; }
    int32 GetBudget() const { return TotalBudget; }
    float GetUsagePercent() const
    {
        return (float)CurrentUsage / TotalBudget * 100.0f;
    }

private:
    TArray<FMemoryPool> Pools;
    int32 TotalBudget;
    int32 CurrentUsage = 0;
};
```

### 15.2 Streaming System

```cpp
// Audio streaming management
class FAudioStreamManager
{
public:
    // Stream priorities
    enum class EPriority : uint8
    {
        Low,      // Background ambience
        Normal,   // Regular gameplay sounds
        High,     // Player-related sounds
        Critical  // Music, voice, UI
    };

    // Request stream
    FStreamHandle RequestStream(USoundWave* Sound, EPriority Priority)
    {
        // Check if already streaming
        if (FStreamState* Existing = ActiveStreams.Find(Sound))
        {
            Existing->RefCount++;
            return Existing->Handle;
        }

        // Check budget
        int32 StreamSize = Sound->GetStreamingSize();
        if (CurrentStreamingSize + StreamSize > StreamingBudget)
        {
            // Evict lower priority streams
            EvictStreamsForBudget(StreamSize, Priority);
        }

        // Start streaming
        FStreamState State;
        State.Sound = Sound;
        State.Priority = Priority;
        State.RefCount = 1;
        State.Handle = NextHandle++;

        // Queue async load
        FStreamingManager::Get().RequestAsyncLoad(
            Sound->GetStreamingPath(),
            FAsyncLoadCallback::CreateRaw(this,
                &FAudioStreamManager::OnStreamLoaded, State.Handle)
        );

        ActiveStreams.Add(Sound, State);
        CurrentStreamingSize += StreamSize;

        return State.Handle;
    }

    // Release stream
    void ReleaseStream(FStreamHandle Handle)
    {
        for (auto& Pair : ActiveStreams)
        {
            if (Pair.Value.Handle == Handle)
            {
                Pair.Value.RefCount--;
                if (Pair.Value.RefCount <= 0)
                {
                    // Mark for eviction (not immediate, in case needed again)
                    Pair.Value.EvictionTime = FPlatformTime::Seconds() +
                                             EvictionDelay;
                }
                break;
            }
        }
    }

private:
    TMap<USoundWave*, FStreamState> ActiveStreams;
    int32 StreamingBudget = 64 * 1024 * 1024;  // 64 MB default
    int32 CurrentStreamingSize = 0;
    float EvictionDelay = 5.0f;  // seconds
    FStreamHandle NextHandle = 1;
};
```

### 15.3 Sound Wave Compression

```cpp
// Codec selection based on use case
UENUM()
enum class ESoundWaveLoadingBehavior : uint8
{
    // Load entire sound into memory (small sounds)
    LoadInMemory,

    // Stream from disk (large files, music)
    Stream,

    // Load on demand (rarely used sounds)
    LoadOnDemand,

    // Force inline (always in memory, critical sounds)
    ForceInline
};

// Compression settings per platform
USTRUCT()
struct FPlatformRuntimeAudioCompressionOverrides
{
    GENERATED_BODY()

    // Compression quality (0-100)
    UPROPERTY(EditAnywhere)
    int32 CompressionQuality = 80;

    // Sample rate override
    UPROPERTY(EditAnywhere)
    int32 SampleRateOverride = 0;  // 0 = use source

    // Force mono
    UPROPERTY(EditAnywhere)
    bool bForceMono = false;

    // Use ADPCM (lower quality, lower CPU)
    UPROPERTY(EditAnywhere)
    bool bUseADPCM = false;

    // Streaming chunk size
    UPROPERTY(EditAnywhere)
    int32 StreamingChunkSize = 128 * 1024;  // 128 KB
};
```

---

## 16. Profiling & Optimization

### 16.1 Audio Profiler

```cpp
// Built-in audio profiling
class FAudioProfiler
{
public:
    // Enable profiling
    static void Enable(bool bEnabled);

    // Profile scope
    struct FProfileScope
    {
        FProfileScope(const TCHAR* Name)
        {
            if (bEnabled)
            {
                StartTime = FPlatformTime::Cycles64();
                ScopeName = Name;
            }
        }

        ~FProfileScope()
        {
            if (bEnabled)
            {
                uint64 EndTime = FPlatformTime::Cycles64();
                RecordSample(ScopeName, EndTime - StartTime);
            }
        }

        uint64 StartTime;
        const TCHAR* ScopeName;
    };

    // Get stats
    static FAudioStats GetStats();
};

// Audio statistics
struct FAudioStats
{
    // Voice counts
    int32 ActiveVoices;
    int32 VirtualVoices;
    int32 MaxVoices;

    // CPU usage
    float AudioThreadCPU;     // Percentage
    float MixingCPU;
    float DecodingCPU;
    float EffectsCPU;

    // Memory
    int32 TotalAudioMemory;
    int32 StreamingMemory;
    int32 DecompressedMemory;

    // Streaming
    int32 ActiveStreams;
    int32 PendingStreamRequests;
    float StreamingBandwidth;  // MB/s

    // Latency
    float OutputLatency;      // ms
    float BufferLatency;      // ms
};

// Console commands for debugging
// stat audio       - Basic audio stats
// stat soundcues   - Sound cue stats
// stat soundwaves  - Sound wave stats
// stat soundmixes  - Sound mix stats
// au.Debug.Sounds  - Visual sound debugging
```

### 16.2 Optimization Techniques

```cpp
// Audio optimization best practices
namespace AudioOptimization
{
    // 1. Sound concurrency settings
    UCLASS()
    class USoundConcurrency : public UObject
    {
    public:
        UPROPERTY(EditAnywhere)
        int32 MaxCount = 8;  // Max concurrent instances

        UPROPERTY(EditAnywhere)
        EMaxConcurrentResolutionRule ResolutionRule =
            EMaxConcurrentResolutionRule::StopLowestPriority;

        UPROPERTY(EditAnywhere)
        float VolumeScaleByActivatingPriority = 1.0f;
    };

    // 2. Voice prioritization
    void OptimizeVoicePriority(FSoundSource& Source)
    {
        // Prioritize by audibility
        float Priority = Source.Volume * Source.DistanceAttenuation;

        // Boost player-related sounds
        if (Source.bPlayerRelated)
            Priority *= 2.0f;

        // Boost sounds in focus
        float FocusFactor = CalculateFocusFactor(Source);
        Priority *= FocusFactor;

        Source.Priority = Priority;
    }

    // 3. Distance culling
    bool ShouldCullByDistance(const FSoundSource& Source)
    {
        if (Source.Distance > Source.MaxAudibleDistance)
            return true;

        // Additional culling for non-essential sounds
        if (!Source.bEssential &&
            Source.Distance > Source.MaxAudibleDistance * 0.8f)
        {
            return Source.Volume * Source.DistanceAttenuation < 0.01f;
        }

        return false;
    }

    // 4. Effect chain optimization
    void OptimizeEffectChain(TArray<USoundEffectBase*>& Effects)
    {
        // Remove bypassed effects
        Effects.RemoveAll([](USoundEffectBase* E) { return E->bBypassed; });

        // Combine consecutive EQs
        CombineConsecutiveEQs(Effects);

        // Move filters before reverbs (saves CPU)
        SortEffectsByType(Effects);
    }
}
```

### 16.3 Debug Visualization

```cpp
// Audio debug drawing
void FAudioDebugDraw::DrawDebug(UWorld* World)
{
    if (!bEnabled) return;

    // Draw all active sounds
    for (const FAudioSource& Source : ActiveSources)
    {
        // Draw sound location
        FColor Color = GetColorByPriority(Source.Priority);
        DrawDebugSphere(World, Source.Location, 25.0f, 8, Color);

        // Draw attenuation radius
        if (bShowAttenuation)
        {
            DrawDebugSphere(World, Source.Location,
                          Source.InnerRadius, 16, FColor::Green, false);
            DrawDebugSphere(World, Source.Location,
                          Source.OuterRadius, 16, FColor::Red, false);
        }

        // Draw sound name and info
        if (bShowLabels)
        {
            FString Label = FString::Printf(
                TEXT("%s\nVol: %.2f Pri: %.2f"),
                *Source.SoundName, Source.Volume, Source.Priority);
            DrawDebugString(World, Source.Location + FVector(0, 0, 50),
                          Label, nullptr, Color);
        }

        // Draw line to listener
        if (bShowListenerLines)
        {
            DrawDebugLine(World, Source.Location, ListenerLocation,
                        FColor::Yellow);
        }
    }

    // Draw listener
    DrawDebugDirectionalArrow(World, ListenerLocation,
                             ListenerLocation + ListenerForward * 100.0f,
                             50.0f, FColor::Cyan);
}
```

---

## 17. Plugin Development

### 17.1 Audio Plugin Types

```cpp
// Available plugin interfaces
namespace AudioPlugins
{
    // Spatialization plugin (HRTF, binaural, etc.)
    class ISpatializationPlugin
    {
    public:
        virtual void Spatialize(const FSpatializationParams& Params,
                               FAudioBuffer& OutBuffer) = 0;
    };

    // Reverb plugin (room simulation)
    class IReverbPlugin
    {
    public:
        virtual void ProcessReverb(const FReverbParams& Params,
                                  FAudioBuffer& InOutBuffer) = 0;
    };

    // Occlusion plugin (geometry-based)
    class IOcclusionPlugin
    {
    public:
        virtual float CalculateOcclusion(const FVector& Source,
                                        const FVector& Listener) = 0;
    };

    // Source data override (custom per-source processing)
    class ISourceDataOverridePlugin
    {
    public:
        virtual void ProcessSourceData(FSourceProcessData& Data) = 0;
    };
}
```

### 17.2 Creating Custom Plugin

```cpp
// Example: Custom spatialization plugin
UCLASS()
class UMySpatializationPlugin : public USpatializationPluginSourceSettingsBase
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, Category = "Spatialization")
    float HRTFIntensity = 1.0f;

    UPROPERTY(EditAnywhere, Category = "Spatialization")
    bool bEnableNearFieldEffect = true;
};

class FMySpatializationPluginFactory : public IAudioSpatializationFactory
{
public:
    virtual FString GetDisplayName() override
    {
        return TEXT("My Custom HRTF");
    }

    virtual bool SupportsPlatform(const FString& Platform) override
    {
        return true;  // All platforms
    }

    virtual TAudioSpatializationPtr CreateSpatializationEffect(
        FAudioDevice* AudioDevice) override
    {
        return MakeShared<FMySpatializationEffect>(AudioDevice);
    }
};

class FMySpatializationEffect : public IAudioSpatialization
{
public:
    virtual void ProcessAudio(
        const FAudioPluginSourceInputData& InputData,
        FAudioPluginSourceOutputData& OutputData) override
    {
        // Get settings
        auto* Settings = static_cast<UMySpatializationPlugin*>(
            InputData.SpatializationPluginSettings);

        // Calculate HRTF
        FVector Direction = InputData.SourcePosition - InputData.ListenerPosition;
        Direction.Normalize();

        float Azimuth = FMath::Atan2(Direction.Y, Direction.X);
        float Elevation = FMath::Asin(Direction.Z);

        // Apply HRTF filtering
        ApplyHRTF(InputData.AudioBuffer, OutputData.AudioBuffer,
                 Azimuth, Elevation, Settings->HRTFIntensity);

        // Near-field effect
        if (Settings->bEnableNearFieldEffect)
        {
            float Distance = InputData.SourcePosition.Distance(
                InputData.ListenerPosition);
            if (Distance < 100.0f)  // Within 1 meter
            {
                ApplyNearFieldEffect(OutputData.AudioBuffer, Distance);
            }
        }
    }

private:
    void ApplyHRTF(const FAudioBuffer& Input, FAudioBuffer& Output,
                  float Azimuth, float Elevation, float Intensity);
    void ApplyNearFieldEffect(FAudioBuffer& Buffer, float Distance);
};

// Register plugin
void FMyAudioModule::StartupModule()
{
    IModularFeatures::Get().RegisterModularFeature(
        IAudioSpatializationFactory::GetModularFeatureName(),
        new FMySpatializationPluginFactory());
}
```

### 17.3 Third-Party Plugin Integration

```cpp
// Common third-party audio plugins for UE
namespace ThirdPartyPlugins
{
    // Steam Audio (Valve)
    // - HRTF spatialization
    // - Physics-based reverb
    // - Geometry-based occlusion

    // Oculus Audio SDK
    // - VR-optimized HRTF
    // - Ambisonics support

    // Microsoft Project Acoustics
    // - Wave-based acoustic simulation
    // - Pre-computed propagation

    // Resonance Audio (Google)
    // - Ambisonics encoding/decoding
    // - Room effects

    // Dolby Atmos
    // - Object-based audio
    // - Height channels
}
```

---

## 18. Comparison with Middleware

### 18.1 UE5 Audio vs Wwise

| Feature | UE5 Native | Wwise |
|---------|-----------|-------|
| **Procedural Audio** | MetaSounds (excellent) | Limited |
| **Voice Management** | Basic virtualization | Advanced (virtual voices) |
| **Adaptive Music** | Quartz (good) | Interactive Music (excellent) |
| **Real-time Mixing** | Submix system | States/Snapshots |
| **Profiling** | Built-in stats | Advanced profiler |
| **Integration** | Native | Plugin required |
| **Learning Curve** | Medium | Steep |
| **Cost** | Free (with UE) | Licensed |
| **Multiplatform** | Automatic | Manual per-platform |

### 18.2 UE5 Audio vs FMOD

| Feature | UE5 Native | FMOD |
|---------|-----------|------|
| **Event System** | MetaSounds | FMOD Events |
| **DSP Graph** | MetaSounds | FMOD DSP |
| **Compression** | Platform native | FSB format |
| **Live Update** | Limited | Full support |
| **Tooling** | Integrated in UE | Separate Studio |
| **Team Workflow** | UE source control | FMOD banks |
| **Plugin Ecosystem** | Growing | Established |
| **VR Support** | Native | Plugin |

### 18.3 When to Use Native vs Middleware

**Use UE5 Native Audio when:**
- Procedural audio is primary focus
- Team is small/budget constrained
- Project is UE-exclusive
- MetaSounds meets requirements
- Tight gameplay integration needed

**Consider Middleware when:**
- Complex adaptive music required
- Large audio team needs separate workflow
- Cross-engine compatibility needed
- Advanced voice management required
- Existing investment in middleware

---

## 19. Best Practices

### 19.1 Performance Guidelines

```cpp
// 1. Use appropriate loading behavior
UPROPERTY(EditAnywhere)
ESoundWaveLoadingBehavior LoadingBehavior;

// Short sounds (< 5 sec): LoadInMemory
// Music/ambience: Stream
// Rarely used: LoadOnDemand

// 2. Set proper concurrency
UPROPERTY(EditAnywhere)
USoundConcurrency* ConcurrencySettings;

// Footsteps: Max 4-6 concurrent
// Gunfire: Max 8-12 concurrent
// UI: Max 2-4 concurrent
// Music: Max 1-2 concurrent

// 3. Use sound classes for mix control
UPROPERTY(EditAnywhere)
USoundClass* SoundClass;

// Create hierarchy: Master -> Music/SFX/Voice -> Subcategories

// 4. Leverage virtualization
UPROPERTY(EditAnywhere)
bool bVirtualizeWhenSilent = true;

// 5. Optimize attenuation
UPROPERTY(EditAnywhere)
float CullDistanceScale = 1.0f;  // Reduce for non-essential sounds
```

### 19.2 MetaSounds Best Practices

```cpp
// 1. Use variables for reusable values
// (MetaSounds equivalent of parameters)

// 2. Keep graphs modular
// - Create reusable MetaSound "patches"
// - Use graph references for common patterns

// 3. Optimize node count
// - Combine operations where possible
// - Use built-in math nodes efficiently

// 4. Sample rate considerations
// - Control signals can run at lower rates
// - Audio signals should maintain full sample rate

// 5. Memory management
// - Pre-allocate buffers in custom nodes
// - Avoid allocations in Execute()
```

### 19.3 Submix Organization

```
Recommended Submix Hierarchy:

Master
├── Music
│   ├── Music_Combat
│   ├── Music_Exploration
│   └── Music_Cinematic
├── SFX
│   ├── SFX_Weapons
│   ├── SFX_Footsteps
│   ├── SFX_Environment
│   └── SFX_UI
├── Voice
│   ├── Voice_Dialog
│   └── Voice_VO
├── Reverb (send target)
│   ├── Reverb_Small
│   ├── Reverb_Medium
│   └── Reverb_Large
└── Sidechain (for ducking)
```

---

## 20. FluxForge Integration Points

### 20.1 Applicable Concepts

| UE5 Concept | FluxForge Application |
|-------------|----------------------|
| **MetaSounds** | Inspiration for procedural audio system |
| **Quartz** | Musical timing reference |
| **Submix Graph** | Bus routing architecture |
| **Voice Virtualization** | Voice management system |
| **Audio Modulation** | Parameter automation |
| **Convolution Reverb** | Reverb implementation |

### 20.2 Technical Insights for FluxForge

```rust
// 1. Sample-accurate timing (inspired by Quartz)
pub struct QuartzClock {
    bpm: f64,
    time_signature: (u32, u32),
    sample_rate: f64,
    current_sample: u64,

    // Pre-calculated divisions
    samples_per_beat: u64,
    samples_per_bar: u64,
}

impl QuartzClock {
    pub fn next_quantized_sample(&self, quantization: Quantization) -> u64 {
        let division = match quantization {
            Quantization::Bar => self.samples_per_bar,
            Quantization::Beat => self.samples_per_beat,
            Quantization::Sixteenth => self.samples_per_beat / 4,
            // ...
        };
        ((self.current_sample / division) + 1) * division
    }
}

// 2. Procedural DSP graph (inspired by MetaSounds)
pub trait DspNode: Send {
    fn process(&mut self, context: &ProcessContext);
    fn get_inputs(&self) -> &[DspInput];
    fn get_outputs(&self) -> &[DspOutput];
}

// 3. Submix routing (UE5 style)
pub struct SubmixGraph {
    submixes: Vec<Submix>,
    routing: Vec<SubmixRoute>,
    master: SubmixId,
}

// 4. Voice management with virtualization
pub struct VoiceManager {
    active_voices: Vec<Voice>,
    virtual_voices: Vec<VirtualVoice>,
    max_active: usize,
}
```

### 20.3 Key Takeaways

1. **MetaSounds approach** — Sample-accurate procedural audio is achievable
2. **Integrated tooling** — Native engine integration simplifies workflow
3. **Submix architecture** — Flexible bus routing with effect chains
4. **Quartz timing** — Musical quantization for adaptive audio
5. **Voice virtualization** — Efficient voice management without artifacts
6. **Modulation system** — Global parameter control via buses

---

## Appendix A: Console Commands

```
// Audio debugging
au.Debug.Sounds              - Show all playing sounds
au.Debug.SoundWaves          - Sound wave memory stats
au.Debug.SoundCues           - Sound cue stats
au.Debug.SoundMixes          - Sound mix debug
au.3dVisualize.Enabled 1     - 3D audio visualization

// Performance
stat audio                   - Basic audio stats
stat soundcues              - Sound cue performance
stat soundwaves             - Sound wave stats
stat audiostreaming         - Streaming stats

// MetaSounds
au.MetaSounds.Debug 1       - MetaSound debugging
au.MetaSounds.BlockSize     - Set processing block size

// Voice management
au.VoiceCount.Dump          - Dump voice counts
au.MaxChannels              - Set max concurrent voices

// Reverb
ShowFlag.AudioRadius 1      - Show audio volumes
au.ReverbSubmix             - Reverb submix settings
```

---

## Appendix B: References

- [Unreal Engine Audio Documentation](https://docs.unrealengine.com/audio)
- [MetaSounds Official Guide](https://docs.unrealengine.com/metasounds)
- [Quartz Subsystem Documentation](https://docs.unrealengine.com/quartz)
- [Audio Mixer Technical Reference](https://docs.unrealengine.com/audio-mixer)
- [GDC 2022: UE5 Audio Deep Dive](https://www.gdcvault.com)
- [Unreal Engine Forums - Audio Section](https://forums.unrealengine.com/audio)

---

*Analysis complete. Document serves as reference for FluxForge audio engine development.*
