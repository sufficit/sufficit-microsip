#define PJ_CONFIG_WIN_AUTO   1
#define PJ_IS_BIG_ENDIAN     0
#define PJ_HAS_OPUS_CODEC    1

// To prevent WinVer redefinition issue with VS2022
#define PJ_DONT_NEED_WIN32_VER_HACKS 1

// Explicitly define platform/architecture for broader compatibility
#define _WIN32
#define _M_IX86

#include <pj/config_site_sample.h>