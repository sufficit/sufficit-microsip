// =================================================================================================
// PJSIP CUSTOM CONFIGURATION FILE CONTENT
//
// Author: Hugo Castro de Deco, Sufficit
// Collaboration: Gemini AI for Google
// Date: June 18, 2025
// Version: 2 (Corrected comment block for C/C++ preprocessor compatibility)
//
// This file provides custom configuration definitions for PJSIP,
// including platform-specific settings and feature flags.
// It is intended to be copied to pjlib/include/pj/config_site.h during build.
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

// Add this line to enable PJSIP video functionalities
#define PJMEDIA_HAS_VIDEO 1

// If you are using FFmpeg for video codecs and conversion, ensure these are also enabled if not
// already covered by PJMEDIA_HAS_VIDEO's internal dependencies or other mechanisms.
// Based on the log, these appear to be compiled in pjmedia.vcxproj, so explicit defines might not be strictly necessary
// but can serve as a safeguard or for clarity.
// #define PJMEDIA_HAS_FFMPEG 1
// #define PJMEDIA_HAS_LIBSWSCALE 1

#include <pj/config_site_sample.h>