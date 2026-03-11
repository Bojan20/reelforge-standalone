// au_host.m — ObjC helper for AU plugin hosting (FAST — AUv2 C API)
// Called from Rust via C FFI
// Uses AudioComponentInstanceNew (instant) instead of AVAudioUnit (slow AUv3)

#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioKit/CoreAudioKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AUCocoaUIView.h>

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
        }

        callback(user_data, name, manufacturer,
                 compDesc.componentType, compDesc.componentSubType, compDesc.componentManufacturer);

        comp = AudioComponentFindNext(comp, &desc);
    }
}
