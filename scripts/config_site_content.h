// =================================================================================================
// PJSIP CUSTOM CONFIGURATION FILE
//
// Author: Hugo Castro de Deco, Sufficit
// Collaboration: Gemini AI for Google
// Date: June 16, 2025
// Version: 3
//
// This file provides custom configuration definitions for PJSIP,
// including platform-specific settings and feature flags.
//
// Changes:
//   - Added #ifndef guards around _WIN32_WINNT, _WIN32, and _M_X64 to prevent
//     macro redefinition warnings (C4005).
// =================================================================================================

// Define Windows version for API compatibility (e.g., for WASAPI functions)
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00 // Target Windows 10 (or later for _WIN32_WINNT_WIN10) - 0x0601 for Win 7, 0x0600 for Win Vista
#endif

#define PJ_CONFIG_WIN_AUTO   1
#define PJ_IS_BIG_ENDIAN     0
#define PJ_HAS_OPUS_CODEC    1

// To prevent WinVer redefinition issue with VS2022
#define PJ_DONT_NEED_WIN32_VER_HACKS 1

// Explicitly define platform/architecture for broader compatibility
#ifndef _WIN32
#define _WIN32
#endif

#ifndef _M_X64
#define _M_X64
#endif

#include <pj/config_site_sample.h>
#include <pj/pjsip_extra_defines.h> // Include the new extra defines file