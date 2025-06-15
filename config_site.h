#define PJ_WIN32 1
#define NOMINMAX // Prevent min/max macros from windows.h
#define WIN32_LEAN_AND_MEAN // Reduce size of windows.h, preventing some conflicts
#define PJ_HAS_STANDARD_CTYPE 1 // Use standard ctype.h functions instead of PJSIP wrappers
#define _WIN32_WINNT 0x0601 // Set minimum Windows API version to Windows 7 for compatibility
#define WINVER 0x0601     // Same as _WIN32_WINNT
#include <windows.h>
#define PJ_HAS_IPV6 1
#define PJMEDIA_HAS_OPUS_CODEC 1
#define PJMEDIA_OPUS_DEFAULT_BIT_RATE 32000
#define PJ_LOG_MAX_LEVEL 4
#define PJSUA_MAX_ACC 10
#define PJSUA_MAX_CALLS 32