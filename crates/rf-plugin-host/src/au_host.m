// au_host.m — ObjC helper for AUv3 plugin hosting
// Called from Rust via C FFI

#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioKit/CoreAudioKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AUCocoaUIView.h>

// Callback type for when GUI is ready
typedef void (*AUHostGuiCallback)(void* user_data, NSView* view, double width, double height);

// Store references to keep them alive
static AVAudioUnit* g_audioUnit = nil;
static NSViewController* g_viewController = nil;

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

    [AVAudioUnit instantiateWithComponentDescription:desc
                                             options:kAudioComponentInstantiation_LoadInProcess
                                   completionHandler:^(AVAudioUnit* _Nullable avAudioUnit, NSError* _Nullable error) {
        if (!avAudioUnit) {
            NSLog(@"[au_host] Failed to instantiate: %@", error);
            callback(user_data, nil, 0, 0);
            return;
        }

        g_audioUnit = avAudioUnit;
        NSLog(@"[au_host] AUv3 instantiated OK");

        // Get AUAudioUnit to request view controller
        AUAudioUnit* auAudioUnit = avAudioUnit.AUAudioUnit;

        [auAudioUnit requestViewControllerWithCompletionHandler:^(AUViewControllerBase* _Nullable viewController) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!viewController) {
                    NSLog(@"[au_host] No AUv3 view controller — trying CocoaUI fallback");

                    // Fallback: try kAudioUnitProperty_CocoaUI (AUv2)
                    AudioUnit au = avAudioUnit.audioUnit;
                    UInt32 dataSize = 0;
                    Boolean writable = false;
                    OSStatus status = AudioUnitGetPropertyInfo(au,
                        kAudioUnitProperty_CocoaUI,
                        kAudioUnitScope_Global, 0,
                        &dataSize, &writable);

                    if (status == noErr && dataSize > 0) {
                        AudioUnitCocoaViewInfo* viewInfo = (AudioUnitCocoaViewInfo*)malloc(dataSize);
                        status = AudioUnitGetProperty(au,
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
                                    NSView* view = [factory uiViewForAudioUnit:au withSize:NSMakeSize(800, 600)];
                                    if (view) {
                                        NSLog(@"[au_host] CocoaUI view: %@ frame: %@",
                                              NSStringFromClass([view class]),
                                              NSStringFromRect(view.frame));
                                        double w = MAX(view.frame.size.width, 400);
                                        double h = MAX(view.frame.size.height, 300);
                                        callback(user_data, view, w, h);
                                        free(viewInfo);
                                        // ARC manages factory lifetime automatically
                                        return;
                                    }
                                }
                            }
                        }
                        free(viewInfo);
                    }

                    callback(user_data, nil, 0, 0);
                    return;
                }

                g_viewController = viewController;
                NSView* view = viewController.view;
                NSLog(@"[au_host] AUv3 VC: %@ view: %@ frame: %@",
                      NSStringFromClass([viewController class]),
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
    g_viewController = nil;
    g_audioUnit = nil;
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
