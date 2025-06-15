#define PJ_WIN32 1
#define NOMINMAX // Prevent min/max macros from windows.h
#define WIN32_LEAN_AND_MEAN // Reduce size of windows.h, preventing some conflicts
#define PJ_HAS_STANDARD_CTYPE 1 // Use standard ctype.h functions instead of PJSIP wrappers

// Disable PJSIP's internal definitions of WINVER and _WIN32_WINNT
// This relies on the build environment/SDK setting these correctly via compiler flags.
#define PJ_DONT_NEED_WIN32_VER_HACKS 1

#include <windows.h>
#define PJ_HAS_IPV6 1
#define PJMEDIA_HAS_OPUS_CODEC 1
#define PJMEDIA_OPUS_DEFAULT_BIT_RATE 32000
#define PJ_LOG_MAX_LEVEL 4
#define PJSUA_MAX_ACC 10
#define PJSUA_MAX_CALLS 32