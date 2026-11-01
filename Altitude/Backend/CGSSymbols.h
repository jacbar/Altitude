#ifndef Altitude_CGSSymbols_h
#define Altitude_CGSSymbols_h

#include <ApplicationServices/ApplicationServices.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

/// Resolves private SkyLight / AX symbols via dlsym. Missing symbols do not abort;
/// wrappers return NULL, a failing AXError, false, or 0 as appropriate.

CGSConnectionID AltitudeCGSMainConnectionID(void);

CF_RETURNS_RETAINED
CFArrayRef AltitudeCGSCopyManagedDisplaySpaces(CGSConnectionID cid);

/// Returns false when the move symbol is unavailable.
bool AltitudeCGSMoveWindowsToManagedSpace(
    CGSConnectionID cid,
    CFArrayRef windows,
    CGSSpaceID space
);

CGSSpaceID AltitudeCGSGetActiveSpace(CGSConnectionID cid);

CF_RETURNS_RETAINED
CFArrayRef AltitudeCGSCopySpacesForWindows(
    CGSConnectionID cid,
    int32_t mask,
    CFArrayRef windows
);

AXError AltitudeAXUIElementGetWindow(
    AXUIElementRef element,
    CGWindowID *windowID
);

#endif /* Altitude_CGSSymbols_h */
