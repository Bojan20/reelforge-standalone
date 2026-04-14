// au_host.m — ObjC helper for AU plugin hosting (FAST — AUv2 C API)
// Called from Rust via C FFI
// Uses AudioComponentInstanceNew (instant) instead of AVAudioUnit (slow AUv3)
//
// SECTIONS:
//   1. GUI hosting   — au_host_open_plugin / au_host_close / au_host_scan_plugins
//   2. Audio render  — au_render_create / au_render_process / au_render_* (AUDIO THREAD SAFE)

#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioKit/CoreAudioKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AUCocoaUIView.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1: GUI Hosting (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

// Callback type for when GUI is ready
typedef void (*AUHostGuiCallback)(void* user_data, NSView* view, double width, double height);

// Store references to keep them alive
static AudioComponentInstance g_auInstance = NULL;
static NSView* g_pluginView = nil;

void au_host_open_plugin(
    uint32_t component_type,
    uint32_t component_subtype,
    uint32_t component_manufacturer,
    void* user_data,
    AUHostGuiCallback callback
) {
    AudioComponentDescription desc = {
        .componentType = component_type,
        .componentSubType = component_subtype,
        .componentManufacturer = component_manufacturer,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };

    // FAST PATH: AudioComponentFindNext + AudioComponentInstanceNew (AUv2 C API)
    // This is instant (~1-5ms) vs AVAudioUnit instantiate (~500-2000ms)
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        NSLog(@"[au_host] Component not found type=%08x sub=%08x mfr=%08x",
              component_type, component_subtype, component_manufacturer);
        callback(user_data, nil, 0, 0);
        return;
    }

    AudioComponentInstance auInstance = NULL;
    OSStatus status = AudioComponentInstanceNew(comp, &auInstance);
    if (status != noErr || !auInstance) {
        NSLog(@"[au_host] AudioComponentInstanceNew failed: %d", (int)status);
        callback(user_data, nil, 0, 0);
        return;
    }

    // Initialize the AudioUnit
    status = AudioUnitInitialize(auInstance);
    if (status != noErr) {
        NSLog(@"[au_host] AudioUnitInitialize failed: %d — continuing anyway", (int)status);
    }

    g_auInstance = auInstance;
    NSLog(@"[au_host] AU instantiated (AUv2 fast path)");

    // Try CocoaUI (kAudioUnitProperty_CocoaUI) — most plugins support this
    UInt32 dataSize = 0;
    Boolean writable = false;
    status = AudioUnitGetPropertyInfo(auInstance,
        kAudioUnitProperty_CocoaUI,
        kAudioUnitScope_Global, 0,
        &dataSize, &writable);

    if (status == noErr && dataSize > 0) {
        AudioUnitCocoaViewInfo* viewInfo = (AudioUnitCocoaViewInfo*)malloc(dataSize);
        status = AudioUnitGetProperty(auInstance,
            kAudioUnitProperty_CocoaUI,
            kAudioUnitScope_Global, 0,
            viewInfo, &dataSize);

        if (status == noErr) {
            NSURL* bundleURL = (__bridge_transfer NSURL*)viewInfo->mCocoaAUViewBundleLocation;
            NSString* className = (__bridge_transfer NSString*)viewInfo->mCocoaAUViewClass[0];
            NSBundle* bundle = [NSBundle bundleWithURL:bundleURL];

            if (bundle) {
                Class viewClass = [bundle classNamed:className];
                if (viewClass) {
                    id<AUCocoaUIBase> factory = [[viewClass alloc] init];
                    NSView* view = [factory uiViewForAudioUnit:auInstance withSize:NSMakeSize(800, 600)];
                    if (view) {
                        g_pluginView = view;
                        NSLog(@"[au_host] CocoaUI view: %@ frame: %@",
                              NSStringFromClass([view class]),
                              NSStringFromRect(view.frame));
                        double w = MAX(view.frame.size.width, 400);
                        double h = MAX(view.frame.size.height, 300);
                        free(viewInfo);
                        callback(user_data, view, w, h);
                        return;
                    }
                }
            }
        }
        free(viewInfo);
    }

    // Fallback: try AUv3 requestViewController (slower but covers AUv3-only plugins)
    NSLog(@"[au_host] No CocoaUI — trying AUv3 requestViewController fallback");

    // Wrap in AVAudioUnit for AUv3 API access
    [AVAudioUnit instantiateWithComponentDescription:desc
                                             options:kAudioComponentInstantiation_LoadInProcess
                                   completionHandler:^(AVAudioUnit* _Nullable avAudioUnit, NSError* _Nullable error) {
        if (!avAudioUnit) {
            NSLog(@"[au_host] AUv3 fallback failed: %@", error);
            callback(user_data, nil, 0, 0);
            return;
        }

        AUAudioUnit* auAudioUnit = avAudioUnit.AUAudioUnit;
        [auAudioUnit requestViewControllerWithCompletionHandler:^(AUViewControllerBase* _Nullable viewController) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!viewController) {
                    NSLog(@"[au_host] No AUv3 view controller either");
                    callback(user_data, nil, 0, 0);
                    return;
                }

                NSView* view = viewController.view;
                g_pluginView = view;
                NSLog(@"[au_host] AUv3 VC view: %@ frame: %@",
                      NSStringFromClass([view class]),
                      NSStringFromRect(view.frame));

                double w = MAX(view.frame.size.width, 400);
                double h = MAX(view.frame.size.height, 300);
                callback(user_data, view, w, h);
            });
        }];
    }];
}

void au_host_close(void) {
    g_pluginView = nil;
    if (g_auInstance) {
        AudioUnitUninitialize(g_auInstance);
        AudioComponentInstanceDispose(g_auInstance);
        g_auInstance = NULL;
    }
}

// Scan all AudioUnit plugins
typedef void (*AUHostScanCallback)(void* user_data, const char* name, const char* manufacturer,
                                    uint32_t type, uint32_t subtype, uint32_t mfr_code);

void au_host_scan_plugins(void* user_data, AUHostScanCallback callback) {
    AudioComponentDescription desc = {0, 0, 0, 0, 0};
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);

    while (comp != NULL) {
        CFStringRef cfName = NULL;
        AudioComponentCopyName(comp, &cfName);

        AudioComponentDescription compDesc;
        AudioComponentGetDescription(comp, &compDesc);

        char name[256] = {0};
        char manufacturer[64] = "Unknown";

        if (cfName) {
            CFStringGetCString(cfName, name, sizeof(name), kCFStringEncodingUTF8);
            CFRelease(cfName);

            // Split "Manufacturer: PluginName" format
            char* colon = strchr(name, ':');
            if (colon && colon != name) {
                // manufacturer part is before ':'
                size_t mfr_len = (size_t)(colon - name);
                if (mfr_len >= sizeof(manufacturer)) mfr_len = sizeof(manufacturer) - 1;
                strncpy(manufacturer, name, mfr_len);
                manufacturer[mfr_len] = '\0';
                // Trim leading spaces from plugin name
                char* plugin_name = colon + 1;
                while (*plugin_name == ' ') plugin_name++;
                memmove(name, plugin_name, strlen(plugin_name) + 1);
            }
        }

        callback(user_data, name, manufacturer,
                 compDesc.componentType, compDesc.componentSubType, compDesc.componentManufacturer);

        comp = AudioComponentFindNext(comp, &desc);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2: Audio Render Path (AUDIO THREAD SAFE)
// ─────────────────────────────────────────────────────────────────────────────
// Per Apple AU specification: AudioUnitRender() MUST be callable from any thread
// (including real-time audio thread) after AudioUnitInitialize() returns.
//
// Architecture:
//   - au_render_create()  → allocates AURenderCtx, instantiates AU, sets up stream format
//   - au_render_process() → calls AudioUnitRender() with render callback for input
//   - au_render_set_param() → AudioUnitSetParameter() (audio-thread safe for most AUs)
//   - au_render_get_latency() → kAudioUnitProperty_Latency
//   - au_render_query_params() → enumerate real AU parameters via kAudioUnitProperty_ParameterList
//   - au_render_destroy() → AudioUnitUninitialize() + AudioComponentInstanceDispose()
// ─────────────────────────────────────────────────────────────────────────────

// Max channels we support in the render path
#define AU_MAX_CHANNELS 8

// Context for each render instance (heap-allocated, opaque to Rust)
typedef struct {
    AudioComponentInstance au;     // The AU instance for audio
    AudioTimeStamp          timestamp;
    double                  sample_rate;
    uint32_t                max_frames;
    uint32_t                n_channels;

    // Render callback supplies input samples to AU
    // These pointers are updated each block (au_render_process is synchronous)
    const float*            input_ptrs[AU_MAX_CHANNELS];
    uint32_t                cb_n_frames;
} AURenderCtx;

// Render callback: called by AudioUnitRender to pull input samples into the AU.
// inNumberFrames is the authoritative frame count — always use it exactly.
static OSStatus _au_render_input_callback(
    void*                       inRefCon,
    AudioUnitRenderActionFlags* ioActionFlags,
    const AudioTimeStamp*       inTimeStamp,
    UInt32                      inBusNumber,
    UInt32                      inNumberFrames,
    AudioBufferList*            ioData
) {
    (void)ioActionFlags; (void)inTimeStamp; (void)inBusNumber;

    AURenderCtx* ctx = (AURenderCtx*)inRefCon;
    // inNumberFrames is what the AU actually wants — honor it exactly.
    // cb_n_frames is what Rust gave us; if AU asks for less, copy less (normal).
    // If AU asks for MORE, copy what we have and zero the rest (buffer underrun guard).
    uint32_t available = ctx->cb_n_frames;

    for (uint32_t ch = 0; ch < ioData->mNumberBuffers && ch < AU_MAX_CHANNELS; ch++) {
        if (!ioData->mBuffers[ch].mData) continue;
        float* dst = (float*)ioData->mBuffers[ch].mData;
        if (ctx->input_ptrs[ch]) {
            uint32_t copy_frames = (inNumberFrames < available) ? inNumberFrames : available;
            memcpy(dst, ctx->input_ptrs[ch], copy_frames * sizeof(float));
            // Zero any remaining samples if AU asked for more than we provided
            if (copy_frames < inNumberFrames) {
                memset(dst + copy_frames, 0, (inNumberFrames - copy_frames) * sizeof(float));
            }
        } else {
            // No input for this channel — fill with silence
            memset(dst, 0, inNumberFrames * sizeof(float));
        }
        ioData->mBuffers[ch].mDataByteSize = inNumberFrames * sizeof(float);
    }
    return noErr;
}

// Create an AU instance for audio rendering (NOT GUI).
// Returns opaque AURenderCtx* or NULL on failure.
// MUST be called from non-audio thread (initialization has sync overhead).
void* au_render_create(
    uint32_t component_type,
    uint32_t component_subtype,
    uint32_t component_manufacturer,
    double   sample_rate,
    uint32_t max_frames,
    uint32_t n_channels
) {
    AudioComponentDescription desc = {
        .componentType        = component_type,
        .componentSubType     = component_subtype,
        .componentManufacturer = component_manufacturer,
        .componentFlags       = 0,
        .componentFlagsMask   = 0
    };

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        NSLog(@"[au_render] Component not found: %08x/%08x/%08x",
              component_type, component_subtype, component_manufacturer);
        return NULL;
    }

    AudioComponentInstance au = NULL;
    OSStatus st = AudioComponentInstanceNew(comp, &au);
    if (st != noErr || !au) {
        NSLog(@"[au_render] AudioComponentInstanceNew failed: %d", (int)st);
        return NULL;
    }

    // Clamp channels
    if (n_channels == 0) n_channels = 2;
    if (n_channels > AU_MAX_CHANNELS) n_channels = AU_MAX_CHANNELS;

    // Non-interleaved float32 stream format.
    // Model: 1 bus (bus 0) with n_channels non-interleaved channel buffers.
    // This matches how AudioUnitRender expects a standard stereo/multichannel effect.
    // mChannelsPerFrame = n_channels (total channels on this bus).
    AudioStreamBasicDescription asbd = {
        .mSampleRate       = sample_rate,
        .mFormatID         = kAudioFormatLinearPCM,
        .mFormatFlags      = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket   = sizeof(float),
        .mFramesPerPacket  = 1,
        .mBytesPerFrame    = sizeof(float),
        .mChannelsPerFrame = n_channels,  // All channels on bus 0
        .mBitsPerChannel   = 32,
        .mReserved         = 0
    };

    // Use local variable to track effective channels (may be reduced in fallback below).
    uint32_t effective_channels = n_channels;

    // Set stream format on bus 0 (input and output).
    // Most effect AUs have exactly 1 input bus + 1 output bus.
    OSStatus st2;
    st2 = AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input, 0, &asbd, sizeof(asbd));
    if (st2 != noErr) {
        NSLog(@"[au_render] SetStreamFormat(Input,0) failed: %d — trying with 2ch fallback", (int)st2);
        // Try stereo if n_channels > 2
        if (n_channels > 2) {
            asbd.mChannelsPerFrame = 2;
            AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Input, 0, &asbd, sizeof(asbd));
            AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output, 0, &asbd, sizeof(asbd));
            effective_channels = 2;  // fallback to stereo
        }
    }
    st2 = AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Output, 0, &asbd, sizeof(asbd));
    if (st2 != noErr) {
        NSLog(@"[au_render] SetStreamFormat(Output,0) failed: %d", (int)st2);
    }

    // Set sample rate globally (belt-and-suspenders alongside ASBD)
    st2 = AudioUnitSetProperty(au, kAudioUnitProperty_SampleRate,
                               kAudioUnitScope_Global, 0, &sample_rate, sizeof(double));
    if (st2 != noErr) {
        NSLog(@"[au_render] SetSampleRate failed: %d", (int)st2);
    }

    // Set max frames per slice (must match our block size)
    UInt32 mfps = (UInt32)max_frames;
    st2 = AudioUnitSetProperty(au, kAudioUnitProperty_MaximumFramesPerSlice,
                               kAudioUnitScope_Global, 0, &mfps, sizeof(UInt32));
    if (st2 != noErr) {
        NSLog(@"[au_render] SetMaxFramesPerSlice(%u) failed: %d", mfps, (int)st2);
    }

    // Allocate context (now that we know effective_channels)
    AURenderCtx* ctx = (AURenderCtx*)calloc(1, sizeof(AURenderCtx));
    if (!ctx) {
        AudioComponentInstanceDispose(au);
        return NULL;
    }

    ctx->au          = au;
    ctx->sample_rate = sample_rate;
    ctx->max_frames  = max_frames;
    ctx->n_channels  = effective_channels;

    // Initialize timestamp (mSampleTime tracks playback position)
    memset(&ctx->timestamp, 0, sizeof(AudioTimeStamp));
    ctx->timestamp.mFlags = kAudioTimeStampSampleTimeValid;
    ctx->timestamp.mSampleTime = 0.0;

    // Install render input callback on bus 0 (the standard input bus for effects).
    // The callback provides our input audio to the AU when it calls AudioUnitRender.
    AURenderCallbackStruct renderCb = {
        .inputProc       = _au_render_input_callback,
        .inputProcRefCon = ctx
    };
    OSStatus cbSt = AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback,
                                          kAudioUnitScope_Input, 0, &renderCb, sizeof(AURenderCallbackStruct));
    if (cbSt != noErr) {
        NSLog(@"[au_render] SetRenderCallback failed: %d — instruments don't need it", (int)cbSt);
        // Instrument/Generator AUs don't have input buses — this is expected to fail for them.
    }

    // Initialize the AU (allocates internal state — must be called after properties are set)
    st = AudioUnitInitialize(au);
    if (st != noErr) {
        NSLog(@"[au_render] AudioUnitInitialize failed: %d — plugin may not process", (int)st);
        // Don't fail — some plugins initialize lazily on first render
    }

    CFStringRef cfName = NULL;
    AudioComponentCopyName(comp, &cfName);
    char name[256] = {0};
    if (cfName) {
        CFStringGetCString(cfName, name, sizeof(name), kCFStringEncodingUTF8);
        CFRelease(cfName);
    }
    NSLog(@"[au_render] Created render instance for '%s' (%.0fHz, %u frames, %u ch)",
          name, sample_rate, max_frames, n_channels);

    return ctx;
}

// Process one block of audio through the AU.
// in_ptrs[ch] / out_ptrs[ch] are non-interleaved channel buffers (n_frames samples each).
// AUDIO THREAD SAFE — no Objective-C, no allocations, no locks.
int32_t au_render_process(
    void*         handle,
    const float** in_ptrs,
    float**       out_ptrs,
    uint32_t      n_channels,
    uint32_t      n_frames
) {
    if (!handle) return -1;
    AURenderCtx* ctx = (AURenderCtx*)handle;

    // Update input pointers for the callback
    uint32_t ch_count = (n_channels < ctx->n_channels) ? n_channels : ctx->n_channels;
    ch_count = (ch_count < AU_MAX_CHANNELS) ? ch_count : AU_MAX_CHANNELS;
    ctx->cb_n_frames = n_frames;
    for (uint32_t ch = 0; ch < ch_count; ch++) {
        ctx->input_ptrs[ch] = in_ptrs ? in_ptrs[ch] : NULL;
    }
    for (uint32_t ch = ch_count; ch < AU_MAX_CHANNELS; ch++) {
        ctx->input_ptrs[ch] = NULL;
    }

    // Build AudioBufferList on stack (AU non-interleaved: one buffer per channel)
    // Stack-allocate for up to AU_MAX_CHANNELS channels — no heap allocation.
    struct {
        UInt32        mNumberBuffers;
        AudioBuffer   mBuffers[AU_MAX_CHANNELS];
    } abl;

    abl.mNumberBuffers = ch_count;
    for (uint32_t ch = 0; ch < ch_count; ch++) {
        abl.mBuffers[ch].mNumberChannels = 1;
        abl.mBuffers[ch].mDataByteSize   = n_frames * sizeof(float);
        abl.mBuffers[ch].mData           = out_ptrs ? out_ptrs[ch] : NULL;
    }

    AudioUnitRenderActionFlags flags = 0;
    OSStatus st = AudioUnitRender(ctx->au, &flags,
                                  &ctx->timestamp, 0, (UInt32)n_frames,
                                  (AudioBufferList*)&abl);

    // Advance sample counter
    ctx->timestamp.mSampleTime += n_frames;

    if (st != noErr) {
        // On render error: zero output so no garbage audio
        for (uint32_t ch = 0; ch < ch_count; ch++) {
            if (out_ptrs && out_ptrs[ch]) {
                memset(out_ptrs[ch], 0, n_frames * sizeof(float));
            }
        }
        return (int32_t)st;
    }
    return 0;
}

// Set a parameter value on the AU instance (audio-thread safe for most AUs).
void au_render_set_param(void* handle, uint32_t param_id, float value) {
    if (!handle) return;
    AURenderCtx* ctx = (AURenderCtx*)handle;
    OSStatus st = AudioUnitSetParameter(ctx->au,
                                        (AudioUnitParameterID)param_id,
                                        kAudioUnitScope_Global, 0,
                                        value, 0 /* immediate */);
    if (st != noErr) {
        NSLog(@"[au_render] SetParameter param_id=%u value=%.4f failed: %d", param_id, value, (int)st);
    }
}

// Get plugin latency in samples (call from non-audio thread).
uint32_t au_render_get_latency(void* handle) {
    if (!handle) return 0;
    AURenderCtx* ctx = (AURenderCtx*)handle;
    Float64 latency = 0.0;
    UInt32 size = sizeof(Float64);
    AudioUnitGetProperty(ctx->au, kAudioUnitProperty_Latency,
                         kAudioUnitScope_Global, 0, &latency, &size);
    return (uint32_t)(latency * ctx->sample_rate + 0.5);
}

// Parameter query callback type
typedef void (*AURenderParamCallback)(
    void*       user_data,
    uint32_t    param_id,
    const char* name,
    float       min_val,
    float       max_val,
    float       default_val,
    uint32_t    flags    // kAudioUnitParameterFlag_* bitmask
);

// Enumerate all AU parameters. Call from non-audio thread.
void au_render_query_params(void* handle, void* user_data, AURenderParamCallback callback) {
    if (!handle || !callback) return;
    AURenderCtx* ctx = (AURenderCtx*)handle;

    // Get parameter list
    UInt32 list_size = 0;
    OSStatus st = AudioUnitGetPropertyInfo(ctx->au, kAudioUnitProperty_ParameterList,
                                           kAudioUnitScope_Global, 0, &list_size, NULL);
    if (st != noErr || list_size == 0) return;

    uint32_t param_count = list_size / sizeof(AudioUnitParameterID);
    AudioUnitParameterID* param_ids = (AudioUnitParameterID*)malloc(list_size);
    if (!param_ids) return;

    st = AudioUnitGetProperty(ctx->au, kAudioUnitProperty_ParameterList,
                              kAudioUnitScope_Global, 0, param_ids, &list_size);
    if (st != noErr) { free(param_ids); return; }

    // Query info for each parameter
    AudioUnitParameterInfo info;
    for (uint32_t i = 0; i < param_count; i++) {
        memset(&info, 0, sizeof(info));
        UInt32 info_size = sizeof(AudioUnitParameterInfo);
        st = AudioUnitGetProperty(ctx->au, kAudioUnitProperty_ParameterInfo,
                                  kAudioUnitScope_Global, param_ids[i], &info, &info_size);
        if (st != noErr) continue;

        char name[256] = {0};
        if (info.flags & kAudioUnitParameterFlag_HasCFNameString) {
            // Copy CF string
            if (info.cfNameString) {
                CFStringGetCString(info.cfNameString, name, sizeof(name), kCFStringEncodingUTF8);
                // If we own it, release
                if (info.flags & kAudioUnitParameterFlag_CFNameRelease) {
                    CFRelease(info.cfNameString);
                }
            }
        } else {
            // C string fallback
            strncpy(name, info.name, sizeof(name) - 1);
        }

        callback(user_data,
                 (uint32_t)param_ids[i],
                 name,
                 info.minValue,
                 info.maxValue,
                 info.defaultValue,
                 (uint32_t)info.flags);
    }

    free(param_ids);
}

// Reset the AU render instance (clear internal state, keep setup).
void au_render_reset(void* handle) {
    if (!handle) return;
    AURenderCtx* ctx = (AURenderCtx*)handle;
    AudioUnitReset(ctx->au, kAudioUnitScope_Global, 0);
    ctx->timestamp.mSampleTime = 0.0;
}

// Destroy render instance — uninitialize and dispose AU, free context.
// MUST be called from non-audio thread.
void au_render_destroy(void* handle) {
    if (!handle) return;
    AURenderCtx* ctx = (AURenderCtx*)handle;
    AudioUnitUninitialize(ctx->au);
    AudioComponentInstanceDispose(ctx->au);
    ctx->au = NULL;
    free(ctx);
}
