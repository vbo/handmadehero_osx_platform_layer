// This is a Handmade Hero platform layer prototype implementation for OS X.
// You need to download original game code from handmadehero.org
// to be able to compile and launch the whole thing.

#include "handmade_platform.h" // Pre-order the game to get this file!

// After you've got the source code of the game from handmadehero.org
// you can merge the original code with this code and build
// everything using `./code/osx_build.sh` script.

// This version of platform layer is expected to work with
// day 29 or later version of the game source.
 
// I am compiling the game code in C++ mode but
// this platform layer code gets compiled in Objective-C mode
// because I am using Cocoa API to open a window
// and handle OS events and this API is Objective-C only AFAIK.

// You can launch the whole thing like so:
// $ ../build/osx_handmade.out
// or if you want to use application bundle:
// $ open ./misc/osx_bundle/handmade.app

// Constants, globals and defines
// ==============================

#define DEBUG_TURN_OVERLAY_ON_UNFOCUS 0
#define ARRAY_COUNT(array) (sizeof(array) / sizeof((array)[0]))
#undef internal

static const int framebufferWidth = 1920/2;
static const int framebufferHeight = 1080/2;
static const int initialWindowWidth = framebufferWidth;
static const int initialWindowHeight = framebufferHeight;
static const int targetFPS = 30;
static const double targetFrameTime = (double)1.0/(double)targetFPS;

// We'll initialize this on top of main() function.
static struct {
    int isRunning;
    int onPause;
    char *exeFileName;
    char *exeFilePathEndPointer;
    void *gameMemoryBlock;
    uint64_t gameMemoryBlockSize;
} globalApplicationState;

// Utility Functions
// =================

static void stringConcat(
    int sourceACount, char *sourceA,
    int sourceBCount, char *sourceB,
    char *dest
) {
    for(int index = 0; index < sourceACount; ++index) {
        *dest++ = *sourceA++;
    }
    for(int index = 0; index < sourceBCount; ++index) {
        *dest++ = *sourceB++;
    }
    *dest++ = 0;
}

static int stringLength(char *string) {
    int count = 0;
    while(*string++) ++count;
    return count;
}

#define KILOBYTES(Value) ((Value)*1024LL)
#define MEGABYTES(Value) (KILOBYTES(Value)*1024LL)
#define GIGABYTES(Value) (MEGABYTES(Value)*1024LL)
#define TERABYTES(Value) (GIGABYTES(Value)*1024LL)

// Timing
// ======

#include <mach/mach_time.h>

// I am using mach_absolute_time() to implement a high-resolution timer.
// This function returns time in some CPU-dependent units, so we
// need to obtain and cache a coefficient info to convert it to something usable.
// TODO: maybe use seconds only to talk with game and use usec for calculations?

typedef uint64_t hrtime_t;

static hrtime_t hrtimeStartAbs;
static mach_timebase_info_data_t hrtimeInfo;
static const uint64_t NANOS_PER_USEC = 1000ULL;
static const uint64_t NANOS_PER_MILLISEC = 1000ULL * NANOS_PER_USEC;
static const uint64_t NANOS_PER_SEC = 1000ULL * NANOS_PER_MILLISEC;

// This should be called once before using any timing functions!
// Check out Apple's "Technical Q&A QA1398 Mach Absolute Time Units"
// for official recommendations.
static void osxInitHrtime() {
    hrtimeStartAbs = mach_absolute_time();
    mach_timebase_info(&hrtimeInfo);
}

// Monotonic time in CPU-dependent units.
static hrtime_t osxHRTime() {
   return mach_absolute_time() - hrtimeStartAbs; 
}

// Delta in seconds between two time values in CPU-dependent units.
static double osxHRTimeDeltaSeconds(hrtime_t past, hrtime_t future) {
    double delta = (double)(future - past)
                 * (double)hrtimeInfo.numer
                 / (double)NANOS_PER_SEC
                 / (double)hrtimeInfo.denom;
    return delta;
}

// High-resolution sleep until moment specified by value
// in CPU-dependent units and offset in seconds.
// According to Apple docs this should be in at least 500usec precision.
static void osxHRWaitUntilAbsPlusSeconds(hrtime_t baseTime, double seconds) {
    uint64_t timeToWaitAbs = seconds
                           / (double)hrtimeInfo.numer
                           * (double)NANOS_PER_SEC
                           * (double)hrtimeInfo.denom;
    uint64_t nowAbs = mach_absolute_time();
    mach_wait_until(nowAbs + timeToWaitAbs);
}

// Utility File/Path functions
// ===========================

#include <sys/stat.h>

static void osxExeRelToAbsoluteFilename(
    char * fileName,
    uint32_t destSize, char *dest
) {
    int pathLength = globalApplicationState.exeFilePathEndPointer
                   - globalApplicationState.exeFileName;
    stringConcat(pathLength, globalApplicationState.exeFileName,
        stringLength(fileName), fileName, dest);
}

// stat() function is actually part of POSIX API, nothing OS X specific here.
// TODO: maybe use NSFileManager instead? Which is better?
static int osxGetFileLastWriteTime(char *fileName) {
    int t = 0;
    struct stat fileStat;
    if (stat(fileName, &fileStat) == 0) {
        t = fileStat.st_mtimespec.tv_sec;
    } else {
        // TODO: Diagnostic
    }
    return t;
}

// Debug File I/O
// ==============

#if HANDMADE_INTERNAL

#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

// For some reason the game doesn't pass debug_file_read_result to
// DEBUG_PLATFORM_FREE_FILE_MEMORY implementation so we have no options other
// than malloc()/free() there. Both vm_deallocate and munmap take memory size
// as a parameter and looks like we can't just pass zero there like on win32.

DEBUG_PLATFORM_FREE_FILE_MEMORY(osxDEBUGFreeFileMemory);
void osxDEBUGFreeFileMemory(
    thread_context *thread, void *memory
) {
    if (memory) {
        free(memory);
    }
}

// TODO: Add some error checking.
DEBUG_PLATFORM_READ_ENTIRE_FILE(osxDEBUGReadEntireFile);
debug_read_file_result osxDEBUGReadEntireFile(
    thread_context *thread, char *fileName
) {
    int fileHandle = open(fileName, O_RDONLY);
    struct stat fileStat;
    fstat(fileHandle, &fileStat);
    debug_read_file_result result = {0};
    int size = result.ContentsSize = fileStat.st_size;
    result.Contents = malloc(size);
    read(fileHandle, result.Contents, size);
    close(fileHandle);
    return result;
}

// TODO: Add some error checking.
DEBUG_PLATFORM_WRITE_ENTIRE_FILE(osxDEBUGWriteEntireFile);
bool32 osxDEBUGWriteEntireFile(
    thread_context *thread, char *fileName,
    uint32 memorySize, void *memory
) {
    // TODO: What access perms we should use here?
    int fileHandle = open(fileName, O_WRONLY | O_CREAT, 0777);
    ssize_t writtenSize = write(fileHandle, memory, memorySize);
    close(fileHandle);
    return writtenSize == memorySize;
}

#endif // HANDMADE_INTERNAL

// Integration with Game Code
// ==========================

#include <dlfcn.h>
#include <mach-o/dyld.h>

// Basically API is the same as on Windows:
//  ----------------------------------------------
// | OS X                   | Windows             |
// |----------------------------------------------|
// | dlopen()               | LoadLibrary()       |
// | dlclose()              | FreeLibrary()       |
// | dlsym()                | GetProcAddress()    |
// | _NSGetExecutablePath() | GetModuleFileName() |
//  ----------------------------------------------

typedef struct {
    void *handle;
    int lastWrite;
    int isValid;
    game_update_and_render *updateAndRender;
    game_get_sound_samples *getSoundSamples;
} OSXGameCode;

static void osxCacheExeFilePath(char *buffer, uint32_t bufSize) {
    _NSGetExecutablePath(buffer, &bufSize);
    globalApplicationState.exeFileName = buffer;
    for(char *scan = buffer; *scan; ++scan) {
        if(*scan == '/') {
            globalApplicationState.exeFilePathEndPointer = scan + 1;
        }
    }
}

static OSXGameCode osxLoadGameCode(char *path) {
    OSXGameCode code;
    code.isValid = false;
    code.lastWrite = osxGetFileLastWriteTime(path);
    code.handle = dlopen(path, RTLD_LAZY);
    if (code.handle) {
        dlerror(); // clear last error
        code.updateAndRender =
            (game_update_and_render *) dlsym(code.handle, "GameUpdateAndRender");
        code.getSoundSamples =
            (game_get_sound_samples *) dlsym(code.handle, "GameGetSoundSamples");
        if (code.updateAndRender && code.getSoundSamples) {
            code.isValid = true;
        } else {
            code.updateAndRender = 0;
            code.getSoundSamples = 0;
            // TODO: Diagnostic
        }
    } else {
        // TODO: Diagnostic
    }
    return code;
}

static void osxUnloadGameCode(OSXGameCode *code) {
    if (code->handle) {
        dlclose(code->handle);
        code->handle = 0;
    }
    code->isValid = false;
    code->updateAndRender = 0;
    code->getSoundSamples = 0;
}

// Memory
// ======

#include <sys/mman.h>
#include <string.h>

static void * osxMemoryAllocate(size_t address, size_t size) {
    // Specify address 0 if yot don't care where
    // this memory is allocated. If you do care
    // about memory address use something like
    // 2 TB for address parameter.
    char *startAddress = (char*)address;
    int prot = PROT_READ | PROT_WRITE;
    int flags = MAP_PRIVATE | MAP_ANON;
    if (startAddress != 0) {
        flags |= MAP_FIXED;
    }
    return (uint8_t *)mmap(startAddress, size, prot, flags, -1, 0);
}

inline static void osxMemoryCopy(void *dst, void *src, size_t size) {
    memcpy(dst, src, size);
}

// Input Recording and Playback
// ============================

#include <stdio.h>

// That's basically the same code as in win32 platform layer.
// I am putting input buffer files to /tmp for simplicity.

typedef struct {
    void *memory;
} OSXInputReplayBuffer;

typedef struct {
    OSXInputReplayBuffer replayBuffers[4];
    int recordIndex;
    int recordFileHandle;
    int playIndex;
    int playFileHandle;
} OSXInputPlaybackState;

static void osxInitInputPlayback(OSXInputPlaybackState *state) {
    state->recordIndex = 0;
    state->recordFileHandle = 0;
    state->playIndex = 0;
    state->playFileHandle = 0;
    for (int i = 0; i < ARRAY_COUNT(state->replayBuffers); ++i) {
        OSXInputReplayBuffer *buf = &state->replayBuffers[i];
        // TODO: Experiment with memory-mapped files.
        buf->memory = osxMemoryAllocate(0, globalApplicationState.gameMemoryBlockSize);
    }
}

static void osxGetInputFileLocation(int index, char *dest) {
    sprintf(dest, "/tmp/handmade_loop_%d.hmi", index);
}

static void osxBeginRecordingInput(OSXInputPlaybackState *state, uint32_t index) {
    OSXInputReplayBuffer *replayBuffer = &state->replayBuffers[index];
    state->recordIndex = index;
    char fileName[100];
    osxGetInputFileLocation(index, fileName);
    state->recordFileHandle = open(fileName, O_WRONLY | O_CREAT | O_TRUNC, 0777);
    osxMemoryCopy(
        replayBuffer->memory,
        globalApplicationState.gameMemoryBlock,
        globalApplicationState.gameMemoryBlockSize);
}

static void osxEndRecordingInput(OSXInputPlaybackState *state) {
    close(state->recordFileHandle);
    state->recordIndex = 0;
}

static void osxBeginPlaybackInput(OSXInputPlaybackState *state, uint32_t index) {
    OSXInputReplayBuffer *replayBuffer = &state->replayBuffers[index];
    state->playIndex = index;
    char fileName[100];
    osxGetInputFileLocation(index, fileName);
    state->playFileHandle = open(fileName, O_RDONLY);
    osxMemoryCopy(
        globalApplicationState.gameMemoryBlock,
        replayBuffer->memory,
        globalApplicationState.gameMemoryBlockSize);
}

static void osxEndPlaybackInput(OSXInputPlaybackState *state) {
    close(state->playFileHandle);
    state->playIndex = 0;
}

static void osxRecordInput(OSXInputPlaybackState *state, game_input *input) {
    write(state->recordFileHandle, input, sizeof(*input));
}

static void osxPlayInput(OSXInputPlaybackState *state, game_input *input) {
    int bytesRead = read(state->playFileHandle, input, sizeof(*input));
    if (!bytesRead) {
        int index = state->playIndex;
        osxEndPlaybackInput(state);
        osxBeginPlaybackInput(state, index);
        read(state->playFileHandle, input, sizeof(*input));
    }
}

// Opening Window and Handling Events
// ==================================

#import <Cocoa/Cocoa.h>

// I am trying to use a minimal set of Cocoa features here
// to do things in the spirit of original Handmade Hero.
// E.g. I am rolling my own main event processing loop
// instead of one defined by NSApplication::run()
// to have more control over timing and such.
 
// What I am using to achive this is a sort of hack
// I learned from GLWF library source code:
 
// 1) Create NSApplication
// 2) Configure it to use our custom NSApplicationDelegate
// 3) Issue [NSApp run]
// 4) From our NSApplicationDelegate::applicationDidFinishLaunching()
//    issue [NSApp stop]

// After this is done we get an ability to implement our own
// main loop effectively ignoring the whole Cocoa event dispatch system.
// The point of calling NSApp::run() at all is to allow Cocoa to perform
// any initialization it wants using it's existing code. Some stuff
// does not work well if we skip this step.

@interface ApplicationDelegate
    : NSObject <NSApplicationDelegate, NSWindowDelegate> @end

static NSApplication *cocoaInitApplication() {
    NSApplication *application = [NSApplication sharedApplication];
    // In Snow Leopard, programs without application bundles and
    // Info.plist files don't get a menubar and can't be brought
    // to the front unless the presentation option is changed.
    [application setActivationPolicy: NSApplicationActivationPolicyRegular];
    // Specify application delegate impl.
    ApplicationDelegate *delegate = [[ApplicationDelegate alloc] init];
    [application setDelegate: delegate];
    // Normally this function would block, so if we want
    // to make our own main loop we need to stop it just
    // after initialization (see ApplicationDelegate implementation).
    [application run];
    return application;
}

@implementation ApplicationDelegate : NSObject
    - (void)applicationDidFinishLaunching: (NSNotification *)notification {
        // Stop the event loop after app initialization:
        // I'll make my own loop later.
        [NSApp stop: nil];
        // Post empty event: without it we can't put application to front
        // for some reason (I get this technique from GLFW source).
        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        NSEvent* event =
            [NSEvent otherEventWithType: NSApplicationDefined
                     location: NSMakePoint(0, 0)
                     modifierFlags: 0
                     timestamp: 0
                     windowNumber: 0
                     context: nil
                     subtype: 0
                     data1: 0
                     data2: 0];
        [NSApp postEvent: event atStart: YES];
        [pool drain];
    }

    - (NSApplicationTerminateReply)
      applicationShouldTerminate: (NSApplication *)sender {
        globalApplicationState.isRunning = false;
        return NO;
    }

    - (void)dealloc {
        [super dealloc];
    }
@end

// We can handle most events right from the main loop but some events
// like window focus (aka windowDidBecomeKey) could only be handled
// by custom NSWindowDelegate. Or maybe I am missing something?

@interface WindowDelegate:
    NSObject <NSWindowDelegate> @end

@implementation WindowDelegate : NSObject
    - (BOOL)windowShouldClose: (id)sender {
        globalApplicationState.isRunning = false;
        return NO;
    }

    - (void)windowDidBecomeKey: (NSNotification *)notification {
#if DEBUG_TURN_OVERLAY_ON_UNFOCUS
        NSWindow *window = [notification object];
        [window setLevel: NSNormalWindowLevel];
        [window setAlphaValue: 1];
        [window setIgnoresMouseEvents: NO];
#endif
    }

    - (void)windowDidResignKey: (NSNotification *)notification {
#if DEBUG_TURN_OVERLAY_ON_UNFOCUS
        NSWindow *window = [notification object];
        [window setLevel: NSMainMenuWindowLevel];
        [window setAlphaValue: 0.3];
        [window setIgnoresMouseEvents: YES];
#endif
    }
@end

static inline void cocoaProcessKeyUpDown(game_button_state *state, int isDown) {
    if(state->EndedDown != isDown) {
        state->EndedDown = isDown;
        ++state->HalfTransitionCount;
    }
}

// Flushes event queue, handling most of the events in place.
// This should be called every frame or our window become unresponsive!
// TODO: For some reason the whole thing hangs on window resize events: investigate.
void cocoaFlushEvents(
    NSApplication *application,
    game_controller_input *keyboardController,
    OSXInputPlaybackState *playback
) {
    NSAutoreleasePool *eventsAutoreleasePool = [[NSAutoreleasePool alloc] init];
    while (true) {
        NSEvent* event =
            [application nextEventMatchingMask: NSAnyEventMask
                         untilDate: [NSDate distantPast]
                         inMode: NSDefaultRunLoopMode
                         dequeue: YES];
        if (!event) {
            break;
        }
        switch ([event type]) {
            case NSKeyUp:
            case NSKeyDown: {
                int hotkeyMask = NSCommandKeyMask
                               | NSAlternateKeyMask
                               | NSControlKeyMask
                               | NSAlphaShiftKeyMask;
                if ([event modifierFlags] & hotkeyMask) {
                    // Handle events like cmd+q etc
                    [application sendEvent:event];
                    break;
                }
                // Handle normal keyboard events in place.
                int isDown = ([event type] == NSKeyDown);
                switch ([event keyCode]) {
                    case 13: { // W
                        cocoaProcessKeyUpDown(
                            &keyboardController->MoveUp, isDown);
                    } break;
                    case 0: { // A
                        cocoaProcessKeyUpDown(
                            &keyboardController->MoveLeft, isDown);
                    } break;
                    case 1: { // S
                        cocoaProcessKeyUpDown(
                            &keyboardController->MoveDown, isDown);
                    } break;
                    case 2: { // D
                        cocoaProcessKeyUpDown(
                            &keyboardController->MoveRight, isDown);
                    } break;
                    case 12: { // Q
                        cocoaProcessKeyUpDown(
                            &keyboardController->LeftShoulder, isDown);
                    } break;
                    case 14: { // E
                        cocoaProcessKeyUpDown(
                            &keyboardController->RightShoulder, isDown);
                    } break;
                    case 126: { // Up
                        cocoaProcessKeyUpDown(
                            &keyboardController->ActionUp, isDown);
                    } break;
                    case 123: { // Left
                        cocoaProcessKeyUpDown(
                            &keyboardController->ActionLeft, isDown);
                    } break;
                    case 125: { // Down
                        cocoaProcessKeyUpDown(
                            &keyboardController->ActionDown, isDown);
                    } break;
                    case 124: { // Right
                        cocoaProcessKeyUpDown(
                            &keyboardController->ActionRight, isDown);
                    } break;
                    case 53: { // Esc
                        cocoaProcessKeyUpDown(
                            &keyboardController->Start, isDown);
                    } break;
                    case 49: { // Space
                        cocoaProcessKeyUpDown(
                            &keyboardController->Back, isDown);
                    } break;
                    case 35: { // P
                        if (isDown) {
                            globalApplicationState.onPause = !globalApplicationState.onPause;
                        }
                    } break;
                    case 37: { // L
                        if (isDown) {
                            if (playback->playIndex == 0) {
                                if (playback->recordIndex == 0) {
                                    osxBeginRecordingInput(playback, 1);
                                } else {
                                    osxEndRecordingInput(playback);
                                    osxBeginPlaybackInput(playback, 1);
                                }
                            } else {
                                osxEndPlaybackInput(playback);
                            }
                        }
                    } break;
                    default: {
                        // Uncomment to learn your keys:
                        //NSLog(@"Unhandled key: %d", [event keyCode]);
                    } break;
                }
            } break;
            default: {
                // Handle events like app focus/unfocus etc
                [application sendEvent:event];
            } break;
        }
    }
    [eventsAutoreleasePool drain];
}

// Creates window and minimalistic menu.
// I have not found a way to change application name programmatically
// so if you run this without application bundle you see something
// like osx_handmade.out.
// TODO: Is there a way to specify application name from code?
static NSWindow *cocoaCreateWindowAndMenu(
    NSApplication *application,
    int width, int height
) {
    int windowStyleMask = NSClosableWindowMask
                        | NSMiniaturizableWindowMask
                        | NSTitledWindowMask
                        | NSResizableWindowMask;
    NSRect windowRect = NSMakeRect(0, 0, width, height);
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect: windowRect
                          styleMask: windowStyleMask
                          backing: NSBackingStoreBuffered
                          defer: NO];
    [window center];
    WindowDelegate *windowDelegate = [[WindowDelegate alloc] init];
    [window setDelegate: windowDelegate];
    id appName = @"Handmade Hero";
    NSMenu *menubar = [NSMenu alloc];
    [window setTitle: appName];
    NSMenuItem *appMenuItem = [NSMenuItem alloc];
    [menubar addItem: appMenuItem];
    [application setMainMenu: menubar];
    NSMenu *appMenu = [NSMenu alloc];
    id quitTitle = [@"Quit " stringByAppendingString: appName];
    // Make menu respond to cmd+q
    id quitMenuItem =
        [[NSMenuItem alloc] initWithTitle: quitTitle
                            action: @selector(terminate:)
                            keyEquivalent: @"q"];
    [appMenu addItem: quitMenuItem];
    [appMenuItem setSubmenu: appMenu];
    // When running from console we need to manually steal focus
    // from the terminal window for some reason.
    [application activateIgnoringOtherApps:YES];
    // A cryptic way to ask window to open.
    [window makeKeyAndOrderFront: application];
    return window;
}

// Handling Gamepad Input
// ======================

#include <IOKit/hid/IOHIDLib.h>
#include <Kernel/IOKit/hidsystem/IOHIDUsageTables.h>

// I am using IOKit IOHID API to handle gamepad input.
// The main idea is to use IOHIDManager API to subscribe for
// device plug-in events. When some compatible device plug-ins
// we choose an empty controller slot for it and subscribe for
// actual USB HID value change notifications (button presses
// and releases, stick movement etc). When device gets unplugged
// we mark the corresponding controller slot as disconnected
// and unsubscribe from all related events.

// Check out Apple's HID Class Device Interface Guide
// for official recommendations.

// TODO: I've tested this only with PS3 controller!
// Obviously there should be some controller specific nuances here
// and we need to decide how to handle this properly.
// TODO: Recheck deadzone handling.

static const game_input emptyGameInput;

void iokitControllerValueChangeCallbackImpl(
    void *context, IOReturn result,
    void *sender, IOHIDValueRef valueRef
) {
    game_controller_input *controller = (game_controller_input *)context;
    if (IOHIDValueGetLength(valueRef) > 2) {
        return;
    }
    IOHIDElementRef element = IOHIDValueGetElement(valueRef);
    if (CFGetTypeID(element) != IOHIDElementGetTypeID()) {
        return;
    }
    int usagePage = IOHIDElementGetUsagePage(element);
    int usage = IOHIDElementGetUsage(element);
    CFIndex value = IOHIDValueGetIntegerValue(valueRef);
    // Parsing usagePage/usage/value according to USB HID Usage Tables spec.
    switch (usagePage) {
        case kHIDPage_GenericDesktop: { // Sticks handling.
            float valueNormalized;
            int inDeadZone = false;
            int deadZoneMin = 120;
            int deadZoneMax = 133;
            int center = 128;
            if (value > deadZoneMin && value < deadZoneMax) {
                valueNormalized = 0;
                inDeadZone = true;
            } else {
                if (value > center) {
                    valueNormalized = (float)(value - center + 1) / (float)center;
                } else {
                    valueNormalized = (float)(value - center) / (float)center;
                }
            }
            switch (usage) {
                case kHIDUsage_GD_X: {
                    if (!inDeadZone) {
                        controller->IsAnalog = true;
                    }
                    controller->StickAverageX = valueNormalized;
                } break;
                case kHIDUsage_GD_Y: {
                    if (!inDeadZone) {
                        controller->IsAnalog = true;
                    }
                    controller->StickAverageY = valueNormalized;
                } break;
            }
        } break;
        case kHIDPage_Button: {
            int isDown = (value != 0);
            switch (usage) {
                case 1: { // Select
                    cocoaProcessKeyUpDown(&controller->Back, isDown);
                } break;
                case 4: { // Start
                    cocoaProcessKeyUpDown(&controller->Start, isDown);
                } break;
                case 5: { // D-pad Up
                    cocoaProcessKeyUpDown(&controller->MoveUp, isDown);
                    controller->IsAnalog = false;
                } break;
                case 8: { // D-pad Left
                    cocoaProcessKeyUpDown(&controller->MoveLeft, isDown);
                    controller->IsAnalog = false;
                } break;
                case 7: { // D-pad Down
                    cocoaProcessKeyUpDown(&controller->MoveDown, isDown);
                    controller->IsAnalog = false;
                } break;
                case 6: { // D-pad Right
                    cocoaProcessKeyUpDown(&controller->MoveRight, isDown);
                    controller->IsAnalog = false;
                } break;
                case 13: { // Triangle
                    cocoaProcessKeyUpDown(&controller->ActionUp, isDown);
                } break;
                case 16: { // Square
                    cocoaProcessKeyUpDown(&controller->ActionLeft, isDown);
                } break;
                case 15: { // Cross
                    cocoaProcessKeyUpDown(&controller->ActionDown, isDown);
                } break;
                case 14: { // Circle
                    cocoaProcessKeyUpDown(&controller->ActionRight, isDown);
                } break;
                default: {
                    // Uncomment this to learn you gamepad buttons:
                    //NSLog(@"Unhandled button %d", usage);
                } break;
            }
        } break;
    }
    CFRelease(valueRef);
}

void iokitControllerUnplugCallbackImpl(void* context, IOReturn result, void* sender) {
    game_controller_input *controller = (game_controller_input *)context;
    IOHIDDeviceRef device = (IOHIDDeviceRef)sender;
    controller->IsConnected = false;
    IOHIDDeviceRegisterInputValueCallback(device, 0, 0);
    IOHIDDeviceRegisterRemovalCallback(device, 0, 0);
    IOHIDDeviceUnscheduleFromRunLoop(
        device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
}

void iokitControllerPluginCallbackImpl(
    void* context, IOReturn result,
    void* sender, IOHIDDeviceRef device
) {
    // Find first free controller slot.
    game_input *input = (game_input *)context;
    game_controller_input * controller = 0;
    game_controller_input *controllers = input->Controllers;
    for (size_t i = 0; i < 5; ++i) {
        if (!controllers[i].IsConnected) {
            controller = &controllers[i];
            break;
        }
    }
    // All controller slots are occupied!
    if (!controller) {
        return;
    }
    controller->IsConnected = true;
    IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    IOHIDDeviceScheduleWithRunLoop(
        device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    // Subscribe for this device events.
    // I am passing actual controller pointer as a callback
    // so we can distinguish between events from different
    // controllers.
    IOHIDDeviceRegisterInputValueCallback(
        device, iokitControllerValueChangeCallbackImpl, (void *)controller);
    IOHIDDeviceRegisterRemovalCallback(
        device, iokitControllerUnplugCallbackImpl, (void *)controller);
}

// Utility function to prepare input for IOHIDManager.
// Creates a CoreFoundation-style dictionary like this:
//   kIOHIDDeviceUsagePageKey => usagePage
//   kIOHIDDeviceUsageKey => usageValue
static CFMutableDictionaryRef iokitCreateDeviceMatchingDict(
    uint32_t usagePage, uint32_t usageValue
) {
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFNumberRef pageNumber = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberIntType, &usagePage);
    CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsagePageKey), pageNumber);
    CFRelease(pageNumber);
    CFNumberRef usageNumber = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberIntType, &usageValue);
    CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsageKey), usageNumber);
    CFRelease(usageNumber);
    return result;
}

// Our job here is to just subscribe for device plug-in events
// for all device types we want to support.
static void iokitInit(game_input *input) {
    IOHIDManagerRef hidManager = IOHIDManagerCreate(
        kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    uint32_t matches[] = {
        kHIDUsage_GD_Joystick,
        kHIDUsage_GD_GamePad,
        kHIDUsage_GD_MultiAxisController
    };
    CFMutableArrayRef deviceMatching = CFArrayCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    for (int i = 0; i < ARRAY_COUNT(matches); ++i) {
        CFDictionaryRef matching = iokitCreateDeviceMatchingDict(
            kHIDPage_GenericDesktop, matches[i]);
        CFArrayAppendValue(deviceMatching, matching);
        CFRelease(matching);
    }
    IOHIDManagerSetDeviceMatchingMultiple(hidManager, deviceMatching);
    CFRelease(deviceMatching);
    IOHIDManagerRegisterDeviceMatchingCallback(
        hidManager, iokitControllerPluginCallbackImpl, input);
    IOHIDManagerScheduleWithRunLoop(
        hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

// Drawing Pixels to the Screen
// ============================

#import <OpenGL/gl.h>

// I am using OpenGL here to draw the results of game
// rendering to the screen. The main idea is to allocate
// texture of the size of the game drawing surface and
// update this texture data with actual bitmap drawn by the game
// on each main loop iteration.

// To actually draw this texture to the screen I am simply mapping
// it to the full-viewport quad using OpenGL fixed-function API.

typedef struct {
    NSOpenGLContext *context;
    GLuint framebufferTextureId;
    int framebufferWidth;
    int framebufferHeight;
} OpenglState;

// Creates OpenGL context and initializes a drawing surface.
NSOpenGLContext *openglCreateContext(NSWindow *window) {
    NSOpenGLContext *openglContext;
    NSOpenGLPixelFormatAttribute attributes[10];
    int unsigned attrCount = 0;
    // Only accelerated renders.
    attributes[attrCount++] = NSOpenGLPFAAccelerated;
    // Indicates that the pixel format choosing policy is altered
    // for the color buffer such that the buffer closest to the requested size
    // is preferred, regardless of the actual color buffer depth
    // of the supported graphics device.
    attributes[attrCount++] = NSOpenGLPFAClosestPolicy;
    // Request double-buffered format.
    attributes[attrCount++] = NSOpenGLPFADoubleBuffer;
    // Request no multisampling.
    attributes[attrCount++] = NSOpenGLPFASampleBuffers;
    attributes[attrCount++] = 0;
    // This is just for end of array.
    attributes[attrCount++] = 0;
    // Create actual context with this attributes.
    NSOpenGLPixelFormat *pixelFormat =
        [[NSOpenGLPixelFormat alloc] initWithAttributes: attributes];
    openglContext =
        [[NSOpenGLContext alloc] initWithFormat: pixelFormat
                                 shareContext: 0];
    if (!openglContext) {
        // TODO: logging
        return 0;
    }
    // We have only one context so just make it current here
    // and don't think about it to much.
    [openglContext makeCurrentContext];
    // Enable vSync.
    GLint vsync = 1;
    [openglContext setValues: &vsync
                   forParameter: NSOpenGLCPSwapInterval];
    // Substitute window's default contentView with OpenGL view
    // and configure it to use our newly created OpenGL context.
    NSOpenGLView *view = [[NSOpenGLView alloc] init];
    [view setWantsBestResolutionOpenGLSurface: YES];
    [window setContentView: view];
    [view setOpenGLContext: openglContext];
    [view setPixelFormat: pixelFormat];
    [openglContext setView: view];
    return openglContext;
}

void openglInitState(
    OpenglState *state,
    NSWindow *window,
    int framebufferWidth,
    int framebufferHeight
) {
    state->context = openglCreateContext(window);
    state->framebufferWidth = framebufferWidth;
    state->framebufferHeight = framebufferHeight;
    // Prepare texture to draw our bitmap to.
    glEnable(GL_TEXTURE_2D);
    glClearColor(1, 0, 1, 1);
    glDisable(GL_DEPTH_TEST);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &state->framebufferTextureId);
    glBindTexture(GL_TEXTURE_2D, state->framebufferTextureId);
    // Specify texture parameters.
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    // Allocate texture storage and specify how to read values from it.
    // Last NULL means that we don't have data right now and just want OpenGL
    // to allocate memory for the texture of a particular size.
    glTexImage2D(
        GL_TEXTURE_2D, 0, GL_RGBA,
        state->framebufferWidth, state->framebufferHeight,
        0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
}

void openglUpdateFramebufferAndFlush(OpenglState *state, void *framebufferMemory) {
    glClear(GL_COLOR_BUFFER_BIT);
    // Upload new video frame to the GPU.
    glTexSubImage2D(
        GL_TEXTURE_2D, 0, 0, 0,
        state->framebufferWidth, state->framebufferHeight,
        GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, framebufferMemory);
    // Draw textured full-viewport quad.
    glBegin(GL_QUADS); {
        glTexCoord2f(0.0f, 1.0f); glVertex2f(-1.0f, -1.0f);
        glTexCoord2f(1.0f, 1.0f); glVertex2f( 1.0f, -1.0f);
        glTexCoord2f(1.0f, 0.0f); glVertex2f( 1.0f,  1.0f);
        glTexCoord2f(0.0f, 0.0f); glVertex2f(-1.0f,  1.0f);
    } glEnd();
    // Swap OpenGL buffers. With vSync enabled this
    // will always block us until refresh boundary.
    [state->context flushBuffer];
}

// Audio output
// ============

#import <AudioUnit/AudioUnit.h>

// I am using CoreAudio AudioUnit API here. The main idea
// is to create an AudioUnit configured to output
// PCM data to the standard output device specifying
// so called render callback to be called when
// AudioUnit needs more audio data from the application.

// This callback will be called from the separated thread
// several times per frame so we need to buffer data
// we read from the game and read from this buffer
// from the callback.

// I am using a sort of DirectSound-like API with ring-buffer
// data structure and two pointers to it: playCursor and writeCursor.

typedef struct
{
    uint32_t isValid;
    uint32_t samplesPerSecond;
    uint32_t playCursor;
    uint32_t writeCursor;
    uint64_t runningSampleIndex;
    int16_t *buffer;
    uint32_t bufferSizeInSamples;
} CoreAudioOutputState;

// Actual callback implementation is a bit janky due to thread-safety
// issues and ring-buffer complexities.

#include "libkern/OSAtomic.h"

OSStatus audioRenderCallbackImpl(
    void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
    const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
    UInt32 inNumberFrames, AudioBufferList* ioData
) {
    CoreAudioOutputState *state = (CoreAudioOutputState *)inRefCon;
    int addWriteCursor = inNumberFrames;
    uint32_t newWriteCursor = state->writeCursor + inNumberFrames;
    if (newWriteCursor >= state->bufferSizeInSamples) {
        addWriteCursor = addWriteCursor - state->bufferSizeInSamples;
    }
    OSAtomicAdd32(addWriteCursor, (int32_t *)&state->writeCursor);
    AudioUnitSampleType *leftSamples = ioData->mBuffers[0].mData;
    AudioUnitSampleType *rightSamples = ioData->mBuffers[1].mData;
    for (int i = 0; i < inNumberFrames; ++i) {
        leftSamples[i] = (float)state->buffer[state->playCursor*2] / 32768.0;
        rightSamples[i] = (float)state->buffer[state->playCursor*2 + 1] / 32768.0;
        int addPlayCursor = 1;
        uint32_t newPlayCursor = state->playCursor + addPlayCursor;
        if (newPlayCursor == state->bufferSizeInSamples) {
            addPlayCursor = addPlayCursor - state->bufferSizeInSamples;
        }
        OSAtomicAdd32(addPlayCursor, (int32_t *)&state->playCursor);
    }
    return noErr;
}

AudioUnit coreAudioCreateOutputUnit(CoreAudioOutputState *state) {
    AudioUnit outputUnit;
    // Find default AudioComponent.
    AudioComponent outputComponent; {
        AudioComponentDescription description = {
            kAudioUnitType_Output,
            kAudioUnitSubType_DefaultOutput,
            kAudioUnitManufacturer_Apple
        };
        outputComponent = AudioComponentFindNext(NULL, &description);
    }
    // Initialize output AudioUnit.
    AudioComponentInstanceNew(outputComponent, &outputUnit);
    AudioUnitInitialize(outputUnit);
    // Prepare stream description.
    AudioStreamBasicDescription audioFormat; {
        audioFormat.mSampleRate = (float)state->samplesPerSecond;
        audioFormat.mFormatID = kAudioFormatLinearPCM;
        // TODO: maybe switch to 16-bit PCM here?
        audioFormat.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;
        audioFormat.mFramesPerPacket = 1;
        audioFormat.mBytesPerFrame = sizeof(AudioUnitSampleType);
        audioFormat.mBytesPerPacket =
            audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame;
        audioFormat.mChannelsPerFrame = 2; // 2 for stereo
        audioFormat.mBitsPerChannel = 8 * sizeof(AudioUnitSampleType);
        audioFormat.mReserved = 0;
    }
    // Configure AudioUnit.
    AudioUnitSetProperty(
        outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
        0, &audioFormat, sizeof(audioFormat));
    // Specify RenderCallback.
    AURenderCallbackStruct renderCallback = {audioRenderCallbackImpl, state};
    AudioUnitSetProperty(
        outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global,
        0, &renderCallback, sizeof(renderCallback));
    return outputUnit;
}

void coreAudioCopySamplesToRingBuffer(
    CoreAudioOutputState *state,
    game_sound_output_buffer *source,
    int samplesCount
) {
    int realWriteCursor = state->runningSampleIndex % state->bufferSizeInSamples;
    int sampleIndex = 0;
    for (int i = 0; i < samplesCount; ++i) {
        state->buffer[realWriteCursor*2] = source->Samples[sampleIndex++];
        state->buffer[realWriteCursor*2 + 1] = source->Samples[sampleIndex++];
        realWriteCursor++;
        realWriteCursor = realWriteCursor % state->bufferSizeInSamples;
        state->runningSampleIndex++;
    }
}

// Putting It All Together
// =======================

int main() {
    osxInitHrtime();
    char exeFileNameBuf[MAXPATHLEN];
    osxCacheExeFilePath(exeFileNameBuf, MAXPATHLEN);
    char gameDylibFullPath[MAXPATHLEN];
    osxExeRelToAbsoluteFilename("handmade.dylib", MAXPATHLEN, gameDylibFullPath);
    game_input input = emptyGameInput;
    game_controller_input *keyboardController = &input.Controllers[0];
    // Keyboard should be connected before IOKit init
    // or we may accidentally assign controller to it's slot.
    keyboardController->IsConnected = true;
    iokitInit(&input);
    globalApplicationState.isRunning = true;
    // Load game code dynamically so we can reload it later
    // to enable live-edit.
    OSXGameCode game = osxLoadGameCode(gameDylibFullPath);
    // Allocate game memory.
    game_memory gameMemory = {0}; {
        gameMemory.IsInitialized = 0;
        gameMemory.PermanentStorageSize = MEGABYTES(64);
        gameMemory.TransientStorageSize = GIGABYTES(1);
        int64_t startAddress = TERABYTES(2);
        globalApplicationState.gameMemoryBlockSize =
            gameMemory.PermanentStorageSize + gameMemory.TransientStorageSize;
        globalApplicationState.gameMemoryBlock = osxMemoryAllocate(
            startAddress, globalApplicationState.gameMemoryBlockSize);
        gameMemory.PermanentStorage = globalApplicationState.gameMemoryBlock;
        gameMemory.TransientStorage = (
            (uint8_t *)gameMemory.PermanentStorage + gameMemory.PermanentStorageSize);
#if HANDMADE_INTERNAL
        gameMemory.DEBUGPlatformFreeFileMemory = osxDEBUGFreeFileMemory;
        gameMemory.DEBUGPlatformReadEntireFile = osxDEBUGReadEntireFile;
        gameMemory.DEBUGPlatformWriteEntireFile = osxDEBUGWriteEntireFile;
#endif
    }
    // Allocate framebuffer.
    game_offscreen_buffer framebuffer = {0}; {
        framebuffer.Width = framebufferWidth;
        framebuffer.Height = framebufferHeight;
        framebuffer.BytesPerPixel = 4;
        framebuffer.Pitch = framebuffer.Width * framebuffer.BytesPerPixel;
        size_t size = framebuffer.Width * framebuffer.Height * framebuffer.BytesPerPixel;
        framebuffer.Memory = osxMemoryAllocate(0, size);
        // Initialize framebuffer with zeroes
        // so we can draw it right away.
        uint8_t *pixel = (uint8_t *)framebuffer.Memory;
        int framebufferSize = framebuffer.Width * framebuffer.Height * framebuffer.BytesPerPixel;
        while(framebufferSize--) {
            *pixel++ = 0;
        }
    }
    // Allocate sound buffers.
    int soundSamplesPerSecond = 48000;
     // 16-bit for each stereo channel
    int soundBytesPerSample = 2 * sizeof(int16_t);
    int bufferSizeInSamples = soundSamplesPerSecond;
    int soundBufferSizeInBytes = bufferSizeInSamples * soundBytesPerSample;
    CoreAudioOutputState soundOutputState = {0}; {
        soundOutputState.isValid = false;
        soundOutputState.samplesPerSecond = soundSamplesPerSecond;
        soundOutputState.playCursor = 0;
        // Introduce some safe initial latency.
        soundOutputState.writeCursor = 20.0/1000.0 * soundSamplesPerSecond;
        soundOutputState.bufferSizeInSamples = bufferSizeInSamples;
        soundOutputState.buffer = osxMemoryAllocate(0, soundBufferSizeInBytes);
        for (int i = 0; i < bufferSizeInSamples * 2; ++i) {
            soundOutputState.buffer[i] = 0;
        }
    }
    game_sound_output_buffer gameSoundBuffer = {0}; {
        gameSoundBuffer.SamplesPerSecond = soundSamplesPerSecond;
        gameSoundBuffer.SampleCount = 0;
        gameSoundBuffer.Samples = osxMemoryAllocate(0, soundBufferSizeInBytes); 
    }
    // Initialize thread context.
    thread_context threadContext = {0};
    // Initialize app, window and drawing stuff.
    NSApplication *application = cocoaInitApplication();
    NSWindow *window = cocoaCreateWindowAndMenu(
        application, initialWindowWidth, initialWindowHeight);
    OpenglState openglState = {0};
    openglInitState(&openglState, window, framebufferWidth, framebufferHeight);
    // Initialize audio output.
    AudioUnit outputUnit = coreAudioCreateOutputUnit(&soundOutputState);
    AudioOutputUnitStart(outputUnit);
    // Initialize input playback
    OSXInputPlaybackState inputPlayback;
    osxInitInputPlayback(&inputPlayback);
    // Start main loop.
    hrtime_t timeNow;
    double timeDeltaSeconds = 0;
    hrtime_t timeLast = osxHRTime();
    // For some reason several first iterations
    // are a bit slow so let's just skip them.
    int loopsToSkip = 3;
    while(globalApplicationState.isRunning) {
#if HANDMADE_INTERNAL
        int gameLastWrite = osxGetFileLastWriteTime(gameDylibFullPath);
        if (gameLastWrite > game.lastWrite) {
            osxUnloadGameCode(&game);
            game = osxLoadGameCode(gameDylibFullPath);
        }
#endif
        cocoaFlushEvents(application, keyboardController, &inputPlayback);
        if (!globalApplicationState.onPause) {
            if (!loopsToSkip) {
                input.dtForFrame = timeDeltaSeconds;
                if (inputPlayback.recordIndex) {
                    osxRecordInput(&inputPlayback, &input);
                }
                if (inputPlayback.playIndex) {
                    osxPlayInput(&inputPlayback, &input);
                }
                game.updateAndRender(
                    &threadContext, &gameMemory, &input, &framebuffer);
                // TODO: improve audio synchronization
                uint32_t writeCursor = soundOutputState.writeCursor;
                if (!soundOutputState.isValid) {
                    soundOutputState.runningSampleIndex = writeCursor;
                    soundOutputState.isValid = true;
                }
                uint32_t soundSamplesToRequest = timeDeltaSeconds * soundSamplesPerSecond;
                if (soundSamplesToRequest > soundOutputState.bufferSizeInSamples) {
                    soundSamplesToRequest = soundOutputState.bufferSizeInSamples;
                }
                gameSoundBuffer.SampleCount = soundSamplesToRequest;
                game.getSoundSamples(&threadContext, &gameMemory, &gameSoundBuffer);
                coreAudioCopySamplesToRingBuffer(
                    &soundOutputState, &gameSoundBuffer, soundSamplesToRequest);
                openglUpdateFramebufferAndFlush(&openglState, framebuffer.Memory);
            } else {
                loopsToSkip--;
            }
        }
        // Sleep until the frame boundary.
        // This allows us to use whatever target framerate we want
        // and be independent of vSync.
        while (true) {
            timeNow = osxHRTime();
            timeDeltaSeconds = osxHRTimeDeltaSeconds(timeLast, timeNow);
            double timeToFrame = targetFrameTime - timeDeltaSeconds;
            // We can't sleep precise enough. According to Apple sleep
            // may vary by +500usec sometimes. So:
            // 1) We sleep at all only if we need to wait for more than 2ms
            // 2) We sleep for 1ms less then we need and busy-wait the rest
            if (timeToFrame > 0.002) {
                double timeToSleep = timeToFrame - 0.001;
                osxHRWaitUntilAbsPlusSeconds(timeNow, timeToSleep);
            }
            if (timeToFrame <= 0) {
                break;
            }
        }
        // Update timer
        timeNow = osxHRTime();
        timeDeltaSeconds = osxHRTimeDeltaSeconds(timeLast, timeNow);
        timeLast = timeNow;
    }
    return EXIT_SUCCESS;
}
