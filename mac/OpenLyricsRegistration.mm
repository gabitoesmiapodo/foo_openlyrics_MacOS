#import "stdafx.h"

// Stub for pfc::myassert -- only called when PFC_DEBUG=1 but prebuilt SDK libs are Release
namespace pfc { void myassert(const char*, const char*, unsigned int) {} }

DECLARE_COMPONENT_VERSION("OpenLyrics", "0.0.1",
    "foo_openlyrics\n\n"
    "Open-source lyrics retrieval and display for foobar2000 on macOS.\n"
    "Source: https://github.com/jacquesh/foo_openlyrics\n"
);

VALIDATE_COMPONENT_FILENAME("foo_openlyrics.component");
