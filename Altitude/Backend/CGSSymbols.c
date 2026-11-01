#include "CGSSymbols.h"

#include <dlfcn.h>
#include <pthread.h>

static void *skylightHandle = NULL;
static pthread_once_t skylightOnce = PTHREAD_ONCE_INIT;

static void openSkyLight(void) {
    skylightHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    );
}

static void *skyLightSymbol(const char *name) {
    pthread_once(&skylightOnce, openSkyLight);
    if (skylightHandle == NULL) {
        return NULL;
    }
    return dlsym(skylightHandle, name);
}

typedef CGSConnectionID (*CGSMainConnectionIDFn)(void);
typedef CFArrayRef (*CGSCopyManagedDisplaySpacesFn)(CGSConnectionID);
typedef void (*CGSMoveWindowsToManagedSpaceFn)(CGSConnectionID, CFArrayRef, CGSSpaceID);
typedef CGSSpaceID (*CGSGetActiveSpaceFn)(CGSConnectionID);
typedef CFArrayRef (*CGSCopySpacesForWindowsFn)(CGSConnectionID, int32_t, CFArrayRef);
typedef AXError (*AXUIElementGetWindowFn)(AXUIElementRef, CGWindowID *);

CGSConnectionID AltitudeCGSMainConnectionID(void) {
    static CGSMainConnectionIDFn fn;
    static int resolved = 0;
    if (!resolved) {
        fn = (CGSMainConnectionIDFn)skyLightSymbol("CGSMainConnectionID");
        resolved = 1;
    }
    if (fn == NULL) {
        return 0;
    }
    return fn();
}

CFArrayRef AltitudeCGSCopyManagedDisplaySpaces(CGSConnectionID cid) {
    static CGSCopyManagedDisplaySpacesFn fn;
    static int resolved = 0;
    if (!resolved) {
        fn = (CGSCopyManagedDisplaySpacesFn)skyLightSymbol("CGSCopyManagedDisplaySpaces");
        resolved = 1;
    }
    if (fn == NULL) {
        return NULL;
    }
    return fn(cid);
}

bool AltitudeCGSMoveWindowsToManagedSpace(
    CGSConnectionID cid,
    CFArrayRef windows,
    CGSSpaceID space
) {
    static CGSMoveWindowsToManagedSpaceFn fn;
    static int resolved = 0;
    if (!resolved) {
        fn = (CGSMoveWindowsToManagedSpaceFn)skyLightSymbol("CGSMoveWindowsToManagedSpace");
        resolved = 1;
    }
    if (fn == NULL) {
        return false;
    }
    fn(cid, windows, space);
    return true;
}

CGSSpaceID AltitudeCGSGetActiveSpace(CGSConnectionID cid) {
    static CGSGetActiveSpaceFn fn;
    static int resolved = 0;
    if (!resolved) {
        fn = (CGSGetActiveSpaceFn)skyLightSymbol("CGSGetActiveSpace");
        resolved = 1;
    }
    if (fn == NULL) {
        return 0;
    }
    return fn(cid);
}

CFArrayRef AltitudeCGSCopySpacesForWindows(
    CGSConnectionID cid,
    int32_t mask,
    CFArrayRef windows
) {
    static CGSCopySpacesForWindowsFn fn;
    static int resolved = 0;
    if (!resolved) {
        fn = (CGSCopySpacesForWindowsFn)skyLightSymbol("CGSCopySpacesForWindows");
        resolved = 1;
    }
    if (fn == NULL) {
        return NULL;
    }
    return fn(cid, mask, windows);
}

AXError AltitudeAXUIElementGetWindow(
    AXUIElementRef element,
    CGWindowID *windowID
) {
    static AXUIElementGetWindowFn fn;
    static int resolved = 0;
    if (!resolved) {
        fn = (AXUIElementGetWindowFn)dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
        resolved = 1;
    }
    if (fn == NULL) {
        return kAXErrorFailure;
    }
    return fn(element, windowID);
}
