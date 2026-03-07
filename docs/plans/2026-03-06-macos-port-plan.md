# foo_openlyrics macOS Port -- Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port foo_openlyrics to macOS as a native foobar2000 component with full feature parity to upstream v1.13.

**Architecture:** macOS code lives in `mac/`, shared upstream logic compiled from `src/` with a macOS-compatible stdafx.h and minimal platform shims. Xcode project produces a `.component` bundle. All dependencies statically linked.

**Tech Stack:** C++, Objective-C++, foobar2000 SDK (macOS), Core Text, Core Graphics, vImage, libcurl, pugixml, tidy-html5, cJSON, XCTest + mvtf

**Design doc:** `docs/plans/2026-03-06-macos-port-design.md`

**Reference project:** `/Users/gabito/Sites/foo_vis_projectM` (working macOS foobar2000 component)

---

## Layer 1: Build System + SDK + Xcode Project Skeleton

### Task 1.1: Create build-deps.sh

**Files:**
- Create: `scripts/build-deps.sh`
- Reference: `/Users/gabito/Sites/foo_vis_projectM/scripts/build-deps.sh`

**Step 1: Create the script**

Model after the reference project's `build-deps.sh`. It must:
- Build the 5 foobar2000 SDK Xcode sub-projects as universal static libs (x86_64 + arm64):
  - `pfc/pfc.xcodeproj`
  - `foobar2000/SDK/foobar2000_SDK.xcodeproj`
  - `foobar2000/helpers/foobar2000_SDK_helpers.xcodeproj`
  - `foobar2000/foobar2000_component_client/foobar2000_component_client.xcodeproj`
  - `foobar2000/shared/shared.xcodeproj`
- Build libcurl as a universal static lib with SecureTransport for TLS
- Place SDK libs in their build/Release directories
- Place curl lib in `deps/curl/lib/` and headers in `deps/curl/include/`
- Use `has_all_arches()` helper to skip already-built libs (same as reference)

The foobar2000 SDK must be placed at `deps/foobar2000-sdk/` before running. Provide instructions in the script header for obtaining it.

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="$PROJECT_DIR/deps"
ARCHS=(x86_64 arm64)
ARCHS_CMAKE="x86_64;arm64"

echo "Building dependencies for ${ARCHS[*]}..."

has_all_arches() {
    local file="$1"
    local arch_list
    arch_list="$(lipo -archs "$file" 2>/dev/null || true)"
    for arch in "${ARCHS[@]}"; do
        [[ "$arch_list" == *"$arch"* ]] || return 1
    done
    return 0
}

# 1. Build foobar2000 SDK static libraries
echo ""
echo "=== Building foobar2000 SDK ==="
SDK="$DEPS_DIR/foobar2000-sdk"

if [ ! -d "$SDK" ]; then
    echo "ERROR: foobar2000 SDK not found at $SDK"
    echo "Place the foobar2000 SDK at deps/foobar2000-sdk/ before running."
    exit 1
fi

for proj in \
    "$SDK/pfc/pfc.xcodeproj" \
    "$SDK/foobar2000/SDK/foobar2000_SDK.xcodeproj" \
    "$SDK/foobar2000/helpers/foobar2000_SDK_helpers.xcodeproj" \
    "$SDK/foobar2000/foobar2000_component_client/foobar2000_component_client.xcodeproj" \
    "$SDK/foobar2000/shared/shared.xcodeproj"; do
    echo "  Building $(basename "$proj" .xcodeproj)..."
    xcodebuild -project "$proj" -configuration Release -arch x86_64 -arch arm64 build -quiet
done

echo "SDK libraries built."

# 2. Build libcurl (static, universal)
echo ""
echo "=== Building libcurl ==="
CURL_LIB="$DEPS_DIR/curl/lib"
mkdir -p "$CURL_LIB"

if [ -f "$CURL_LIB/libcurl.a" ] && has_all_arches "$CURL_LIB/libcurl.a"; then
    echo "libcurl universal static lib already built, skipping."
else
    rm -f "$CURL_LIB"/libcurl*.a
    TMPDIR="$(mktemp -d)"
    CURL_VERSION="8.5.0"
    echo "  Downloading curl $CURL_VERSION..."
    curl -sL "https://curl.se/download/curl-$CURL_VERSION.tar.gz" | tar xz -C "$TMPDIR"

    CURL_LIBS=()
    for arch in "${ARCHS[@]}"; do
        echo "  Building for $arch..."
        BUILD_DIR="$TMPDIR/build-$arch"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"
        "$TMPDIR/curl-$CURL_VERSION/configure" \
            --host="$arch-apple-darwin" \
            --prefix="$BUILD_DIR/install" \
            --disable-shared --enable-static \
            --with-secure-transport --without-libpsl \
            --disable-ldap --disable-ldaps --disable-rtsp \
            --disable-dict --disable-telnet --disable-tftp \
            --disable-pop3 --disable-imap --disable-smb \
            --disable-smtp --disable-gopher --disable-mqtt \
            --disable-manual --disable-docs \
            CFLAGS="-arch $arch -mmacosx-version-min=13.0 -O2" \
            > /dev/null 2>&1
        make -j"$(sysctl -n hw.ncpu)" > /dev/null 2>&1
        make install > /dev/null 2>&1
        CURL_LIBS+=("$BUILD_DIR/install/lib/libcurl.a")
    done

    echo "  Creating universal binary..."
    lipo -create "${CURL_LIBS[@]}" -output "$CURL_LIB/libcurl.a"

    # Copy headers
    if [ ! -d "$DEPS_DIR/curl/include" ]; then
        mkdir -p "$DEPS_DIR/curl/include"
        cp -R "$TMPDIR/build-arm64/install/include/curl" "$DEPS_DIR/curl/include/"
    fi

    cd "$PROJECT_DIR"
    rm -rf "$TMPDIR"
    echo "libcurl built and installed to deps/curl/"
fi

echo ""
echo "All dependencies built for ${ARCHS[*]}."
echo ""
echo "SDK static libraries:"
ls "$SDK/pfc/build/Release/"*.a "$SDK/foobar2000/SDK/build/Release/"*.a \
   "$SDK/foobar2000/helpers/build/Release/"*.a \
   "$SDK/foobar2000/foobar2000_component_client/build/Release/"*.a \
   "$SDK/foobar2000/shared/build/Release/"*.a 2>/dev/null
echo ""
echo "libcurl:"
ls "$CURL_LIB"/*.a 2>/dev/null
```

**Step 2: Make executable and test**

Run: `chmod +x scripts/build-deps.sh`

Before running, ensure `deps/foobar2000-sdk/` contains the foobar2000 SDK. The SDK can be obtained from the same source used for the reference project -- check `/Users/gabito/Sites/foo_vis_projectM/deps/foobar2000-sdk/`.

Run: `bash scripts/build-deps.sh`
Expected: All SDK static libs + libcurl built without errors.

**Step 3: Commit**

```bash
git add scripts/build-deps.sh
git commit -m "Add build-deps.sh for foobar2000 SDK and libcurl"
```

---

### Task 1.2: Create run-tests.sh

**Files:**
- Create: `scripts/run-tests.sh`
- Reference: `/Users/gabito/Sites/foo_vis_projectM/scripts/run-tests.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

XCODE_PROJECT="$PROJECT_DIR/mac/openlyrics.xcodeproj"

xcodebuild -project "$XCODE_PROJECT" -scheme openlyrics -destination 'platform=macOS' test
```

**Step 2: Make executable**

Run: `chmod +x scripts/run-tests.sh`

Do not run yet -- the Xcode project doesn't exist yet.

**Step 3: Commit**

```bash
git add scripts/run-tests.sh
git commit -m "Add run-tests.sh for XCTest execution"
```

---

### Task 1.3: Create deploy-component.sh

**Files:**
- Create: `scripts/deploy-component.sh`
- Reference: `/Users/gabito/Sites/foo_vis_projectM/scripts/deploy-component.sh`

**Step 1: Create the script**

Model after the reference. Key differences from reference: component name is `foo_openlyrics.component`, destination dir is `foo_openlyrics`.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

XCODE_PROJECT="$PROJECT_DIR/mac/openlyrics.xcodeproj"
BUILD_DIR="$PROJECT_DIR/mac/build/Release"
COMPONENT_NAME="foo_openlyrics.component"

SRC_COMPONENT="$BUILD_DIR/$COMPONENT_NAME"
SRC_BINARY="$SRC_COMPONENT/Contents/MacOS/foo_openlyrics"

FOOBAR_DIR="$HOME/Library/foobar2000-v2"
USER_COMPONENTS_DIR="$FOOBAR_DIR/user-components"
DEST_DIR="$USER_COMPONENTS_DIR/foo_openlyrics"
DEST_COMPONENT="$DEST_DIR/$COMPONENT_NAME"
DEST_BINARY="$DEST_COMPONENT/Contents/MacOS/foo_openlyrics"

if pgrep -x "foobar2000" >/dev/null 2>&1; then
    echo "foobar2000 is running. Closing it before deploy..."
    osascript -e 'tell application "foobar2000" to quit' >/dev/null 2>&1 || true

    for _ in {1..100}; do
        if ! pgrep -x "foobar2000" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "foobar2000" >/dev/null 2>&1; then
        echo "foobar2000 did not quit gracefully. Forcing termination..."
        pkill -x "foobar2000" >/dev/null 2>&1 || true

        for _ in {1..50}; do
            if ! pgrep -x "foobar2000" >/dev/null 2>&1; then
                break
            fi
            sleep 0.1
        done
    fi

    if pgrep -x "foobar2000" >/dev/null 2>&1; then
        echo "Failed to stop foobar2000. Aborting deploy."
        exit 1
    fi

    echo "foobar2000 closed. Continuing deploy."
fi

if [ "${1:-}" = "--build" ]; then
    if [ "${SKIP_DEPS_BUILD:-0}" != "1" ]; then
        "$SCRIPT_DIR/build-deps.sh"
    fi
    xcodebuild -project "$XCODE_PROJECT" -configuration Release -arch x86_64 -arch arm64 clean build
fi

"$SCRIPT_DIR/run-tests.sh"

if [ ! -d "$SRC_COMPONENT" ]; then
    echo "Built component not found: $SRC_COMPONENT"
    echo "Run: $0 --build"
    exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST_COMPONENT"
cp -R "$SRC_COMPONENT" "$DEST_DIR/"

src_uuid_lines="$(dwarfdump --uuid "$SRC_BINARY" | awk '{print $2, $3}' | sort)"
dst_uuid_lines="$(dwarfdump --uuid "$DEST_BINARY" | awk '{print $2, $3}' | sort)"

echo "Source UUIDs:"
echo "$src_uuid_lines"
echo "Installed UUIDs:"
echo "$dst_uuid_lines"

if [ "$src_uuid_lines" != "$dst_uuid_lines" ]; then
    echo "Install verification failed: UUID mismatch"
    exit 1
fi

echo "Installed: $DEST_COMPONENT"

if [ -d "/Applications/foobar2000.app" ]; then
    open -a "foobar2000"
else
    echo "foobar2000.app not found in /Applications, skipping launch"
fi
```

**Step 2: Make executable**

Run: `chmod +x scripts/deploy-component.sh`

**Step 3: Commit**

```bash
git add scripts/deploy-component.sh
git commit -m "Add deploy-component.sh for build, test, and install workflow"
```

---

### Task 1.4: Create Xcode project skeleton

**Files:**
- Create: `mac/openlyrics.xcodeproj/` (via Xcode or `xcodebuild`)
- Create: `mac/stdafx.h`
- Create: `mac/OpenLyricsRegistration.mm` (minimal, just component version)

This task creates the minimal Xcode project that compiles to a `.component` bundle. The project must:
- Product type: Bundle (`.component`)
- Deployment target: macOS 13.0
- Architectures: x86_64 + arm64
- Link against foobar2000 SDK static libs (pfc, foobar2000_SDK, foobar2000_SDK_helpers, foobar2000_component_client, shared)
- Link against libcurl static lib
- Link against system frameworks: Cocoa, Security, CoreFoundation, SystemConfiguration (for curl)
- Header search paths: `deps/foobar2000-sdk/`, `deps/curl/include/`, `3rdparty/`
- Library search paths: SDK build/Release dirs, `deps/curl/lib/`
- Precompiled header: `mac/stdafx.h`
- Wrapper extension: `component`
- Product name: `foo_openlyrics`
- Info.plist with bundle identifier `com.github.jacquesh.foo-openlyrics`
- Test target: `openlyricsTests` (XCTest)

**Step 1: Create mac/stdafx.h**

```cpp
#ifdef __cplusplus
#include <helpers/foobar2000+atl.h>

#include <algorithm>
#include <chrono>
#include <numeric>
#include <optional>
#include <string>
#include <string_view>
#endif

#ifdef __OBJC__
#include <Cocoa/Cocoa.h>
#endif
```

**Step 2: Create mac/OpenLyricsRegistration.mm**

Minimal registration to verify the build works:

```objc
#import "stdafx.h"

// Stub for pfc::myassert -- only called when PFC_DEBUG=1 but prebuilt SDK libs are Release
namespace pfc { void myassert(const char*, const char*, unsigned int) {} }

DECLARE_COMPONENT_VERSION("OpenLyrics", "0.0.1",
    "foo_openlyrics\n\n"
    "Open-source lyrics retrieval and display for foobar2000 on macOS.\n"
);
```

**Step 3: Create the Xcode project**

Use Xcode to create the project at `mac/openlyrics.xcodeproj` with the settings listed above. Reference `/Users/gabito/Sites/foo_vis_projectM/mac/projectMacOS.xcodeproj` for the exact configuration pattern (build settings, linked libraries, search paths, Info.plist structure).

Key build settings to replicate from reference:
- `WRAPPER_EXTENSION = component`
- `GENERATE_INFOPLIST_FILE = YES`
- `GCC_PRECOMPILE_PREFIX_HEADER = YES`
- `GCC_PREFIX_HEADER = mac/stdafx.h`
- `CLANG_CXX_LANGUAGE_STANDARD = c++20`
- `MACOSX_DEPLOYMENT_TARGET = 13.0`
- `PRODUCT_BUNDLE_IDENTIFIER = com.github.jacquesh.foo-openlyrics`

**Step 4: Build to verify**

Run: `xcodebuild -project mac/openlyrics.xcodeproj -configuration Release -arch x86_64 -arch arm64 build`
Expected: `foo_openlyrics.component` bundle produced in `mac/build/Release/`.

**Step 5: Create minimal XCTest**

Create `mac/tests/OpenLyricsTests.mm`:

```objc
#import <XCTest/XCTest.h>

@interface OpenLyricsTests : XCTestCase
@end

@implementation OpenLyricsTests

- (void)testComponentBundleExists {
    // Placeholder: verify test infrastructure works
    XCTAssertTrue(YES);
}

@end
```

**Step 6: Run tests**

Run: `bash scripts/run-tests.sh`
Expected: 1 test passes.

**Step 7: Deploy to foobar2000**

Run: `bash scripts/deploy-component.sh`
Expected: Component installed, foobar2000 launches, component appears in Components list.

**Step 8: Commit**

```bash
git add mac/ scripts/
git commit -m "Add Xcode project skeleton with minimal component registration"
```

---

## Layer 2: Shared Source Compilation

### Task 2.1: Create PlatformUtil.h / PlatformUtil.mm

**Files:**
- Create: `mac/PlatformUtil.h`
- Create: `mac/PlatformUtil.mm`
- Create: `mac/tests/PlatformUtilTests.mm`

The platform shim provides macOS replacements for Win32 types and functions used by shared source files.

**Step 1: Write tests**

```objc
// mac/tests/PlatformUtilTests.mm
#import <XCTest/XCTest.h>
#include "PlatformUtil.h"

@interface PlatformUtilTests : XCTestCase
@end

@implementation PlatformUtilTests

- (void)testCRectDimensions {
    CRect r{10, 20, 110, 220};
    XCTAssertEqual(r.Width(), 100);
    XCTAssertEqual(r.Height(), 200);
}

- (void)testToTstringIdentity {
    std::string input = "hello";
    std::tstring result = to_tstring(std::string_view(input));
    XCTAssertEqual(result, "hello");
}

- (void)testFromTstringIdentity {
    std::tstring input = "world";
    std::string result = from_tstring(std::tstring_view(input));
    XCTAssertEqual(result, "world");
}

- (void)testIsCharWhitespace {
    XCTAssertTrue(is_char_whitespace(' '));
    XCTAssertTrue(is_char_whitespace('\t'));
    XCTAssertTrue(is_char_whitespace('\n'));
    XCTAssertFalse(is_char_whitespace('a'));
}

- (void)testNormaliseUtf8 {
    std::tstring input = "caf\xC3\xA9";
    std::tstring result = normalise_utf8(std::tstring_view(input));
    XCTAssertFalse(result.empty());
}

@end
```

**Step 2: Run tests to verify they fail**

Run: `bash scripts/run-tests.sh`
Expected: FAIL (PlatformUtil.h not found).

**Step 3: Implement PlatformUtil.h**

```cpp
// mac/PlatformUtil.h
#pragma once

#include <string>
#include <string_view>
#include <cstdint>
#include <vector>

// Win32 type shims for shared source compatibility
using COLORREF = uint32_t;
using TCHAR = char;
using UINT = unsigned int;
using BOOL = int;
using BYTE = uint8_t;
using DWORD = unsigned long;
using HRESULT = long;
using UINT_PTR = uintptr_t;
using WPARAM = uintptr_t;
using LPARAM = intptr_t;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

struct CPoint {
    int x = 0;
    int y = 0;
    CPoint() = default;
    CPoint(int x_, int y_) : x(x_), y(y_) {}
};

struct CSize {
    int cx = 0;
    int cy = 0;
    CSize() = default;
    CSize(int cx_, int cy_) : cx(cx_), cy(cy_) {}
};

struct CRect {
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
    CRect() = default;
    CRect(int l, int t, int r, int b) : left(l), top(t), right(r), bottom(b) {}
    int Width() const { return right - left; }
    int Height() const { return bottom - top; }
};

// On macOS, TCHAR is char and all strings are UTF-8
namespace std {
    using tstring = string;
    using tstring_view = string_view;
}

// String conversion (identity on macOS -- no wide strings)
std::tstring to_tstring(std::string_view string);
std::tstring to_tstring(const std::string& string);
std::tstring to_tstring(const pfc::string8& string);

std::string from_tstring(std::tstring_view string);
std::string from_tstring(const std::tstring& string);

std::tstring normalise_utf8(std::tstring_view input);

bool is_char_whitespace(TCHAR c);
size_t find_first_whitespace(std::tstring_view str, size_t pos = 0);
size_t find_first_nonwhitespace(std::tstring_view str, size_t pos = 0);
size_t find_last_whitespace(std::tstring_view str, size_t pos = std::tstring_view::npos);
size_t find_last_nonwhitespace(std::tstring_view str, size_t pos = std::tstring_view::npos);

// COLORREF helpers
static inline uint8_t GetRValue(COLORREF c) { return (uint8_t)(c & 0xFF); }
static inline uint8_t GetGValue(COLORREF c) { return (uint8_t)((c >> 8) & 0xFF); }
static inline uint8_t GetBValue(COLORREF c) { return (uint8_t)((c >> 16) & 0xFF); }

// HRESULT helper
#define HR_SUCCESS(hr) hr_success(hr, __FILE__, __LINE__)
bool hr_success(HRESULT result, const char* filename, int line_number);
```

**Step 4: Implement PlatformUtil.mm**

```objc
// mac/PlatformUtil.mm
#import "PlatformUtil.h"
#import <Foundation/Foundation.h>
#include <cwctype>

std::tstring to_tstring(std::string_view s) { return std::tstring(s); }
std::tstring to_tstring(const std::string& s) { return s; }
std::tstring to_tstring(const pfc::string8& s) { return std::tstring(s.ptr(), s.length()); }

std::string from_tstring(std::tstring_view s) { return std::string(s); }
std::string from_tstring(const std::tstring& s) { return s; }

std::tstring normalise_utf8(std::tstring_view input) {
    NSString *ns = [[NSString alloc] initWithBytes:input.data()
                                            length:input.size()
                                          encoding:NSUTF8StringEncoding];
    if (!ns) return std::tstring(input);
    NSString *normalised = [ns precomposedStringWithCanonicalMapping];
    return std::tstring([normalised UTF8String], [normalised lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

bool is_char_whitespace(TCHAR c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

size_t find_first_whitespace(std::tstring_view str, size_t pos) {
    for (size_t i = pos; i < str.size(); i++) {
        if (is_char_whitespace(str[i])) return i;
    }
    return std::tstring_view::npos;
}

size_t find_first_nonwhitespace(std::tstring_view str, size_t pos) {
    for (size_t i = pos; i < str.size(); i++) {
        if (!is_char_whitespace(str[i])) return i;
    }
    return std::tstring_view::npos;
}

size_t find_last_whitespace(std::tstring_view str, size_t pos) {
    if (pos == std::tstring_view::npos) pos = str.size() - 1;
    for (size_t i = pos + 1; i > 0; i--) {
        if (is_char_whitespace(str[i - 1])) return i - 1;
    }
    return std::tstring_view::npos;
}

size_t find_last_nonwhitespace(std::tstring_view str, size_t pos) {
    if (pos == std::tstring_view::npos) pos = str.size() - 1;
    for (size_t i = pos + 1; i > 0; i--) {
        if (!is_char_whitespace(str[i - 1])) return i - 1;
    }
    return std::tstring_view::npos;
}

bool hr_success(HRESULT result, const char* filename, int line_number) {
    // On macOS, HRESULT is not used. This stub exists for shared code compatibility.
    (void)filename;
    (void)line_number;
    return result >= 0;
}
```

**Step 5: Add files to Xcode project, run tests**

Run: `bash scripts/run-tests.sh`
Expected: All PlatformUtilTests pass.

**Step 6: Commit**

```bash
git add mac/PlatformUtil.h mac/PlatformUtil.mm mac/tests/PlatformUtilTests.mm
git commit -m "Add PlatformUtil shim for Win32 type compatibility on macOS"
```

---

### Task 2.2: Get shared source files compiling

**Files:**
- Modify: `mac/stdafx.h` (add PlatformUtil include)
- Modify: `src/img_processing.h` (add `#ifdef __APPLE__` guards)
- Modify: Xcode project (add src/ files)

This task adds all reusable `src/` files to the Xcode project and fixes compilation errors.

**Shared files to add to Xcode project (compile from src/ in-place):**
- `src/hash_utils.cpp`
- `src/http.cpp`
- `src/logging.cpp`
- `src/lyric_auto_edit.cpp`
- `src/lyric_data.cpp`
- `src/lyric_io.cpp`
- `src/lyric_metadata.cpp`
- `src/lyric_search.cpp`
- `src/metadb_index_search_avoidance.cpp`
- `src/metrics.cpp`
- `src/tag_util.cpp`
- `src/parsers/lrc.cpp`
- `src/sources/lyric_source.cpp`
- `src/sources/azlyricscom.cpp`
- `src/sources/bandcamp.cpp`
- `src/sources/darklyrics.cpp`
- `src/sources/geniuscom.cpp`
- `src/sources/id3tag.cpp`
- `src/sources/letras.cpp`
- `src/sources/localfiles.cpp`
- `src/sources/lrclib.cpp`
- `src/sources/lyricfind.cpp`
- `src/sources/lyricsify.cpp`
- `src/sources/metalarchives.cpp`
- `src/sources/musixmatch.cpp`
- `src/sources/netease.cpp`
- `src/sources/qqmusic.cpp`
- `src/sources/songlyrics.cpp`

**Step 1: Update mac/stdafx.h to include PlatformUtil**

Add `#include "PlatformUtil.h"` inside the `#ifdef __cplusplus` block, after the foobar2000 include.

**Step 2: Add #ifdef guards to src/img_processing.h**

Guard `CPoint` usage and Windows-only functions:
- `from_colorref(COLORREF)` -- guard with `#ifndef __APPLE__`
- `lerp_offset_image` CPoint parameter -- provide an overload or use `#ifdef`
- `toggle_image_rgba_bgra_inplace` -- guard with `#ifndef __APPLE__`

**Step 3: Add shared source files to Xcode project**

Add all files listed above. Each file's header search path must find both `src/` headers and `mac/` headers (for PlatformUtil.h via stdafx.h).

**Step 4: Fix compilation errors iteratively**

Expect issues in:
- Files that include `win32_util.h` -- PlatformUtil.h provides the same symbols, so either adjust includes with `#ifdef` or ensure PlatformUtil.h is pulled in via stdafx.h
- Files that use `std::format` -- may need `<format>` in stdafx.h or a polyfill if Clang doesn't support it on macOS 13; if unavailable, use `pfc::format()` or snprintf
- Files referencing Windows-only SDK headers (e.g., `resource.h`, `libPPUI/*`) -- these should only appear in UI files which are NOT included
- `img_processing.cpp` -- do NOT add this to the project; it will be replaced by `mac/ImageProcessing.mm`
- `preferences.h` -- check if it references Win32 types beyond what PlatformUtil provides

Work through each compilation error. Prefer minimal `#ifdef __APPLE__` in shared files. If a file needs extensive changes, it may need a macOS-specific version in `mac/`.

**Step 5: Build to verify**

Run: `xcodebuild -project mac/openlyrics.xcodeproj -configuration Release -arch x86_64 -arch arm64 build`
Expected: Clean build, no errors.

**Step 6: Commit**

```bash
git add -A
git commit -m "Add shared source files to Xcode project and fix macOS compilation"
```

---

## Layer 3: Minimal Panel

### Task 3.1: Create OpenLyricsView with static text display

**Files:**
- Create: `mac/OpenLyricsView.h`
- Create: `mac/OpenLyricsView.mm`
- Modify: `mac/OpenLyricsRegistration.mm` (add NSViewController + ui_element_mac)
- Create: `mac/tests/OpenLyricsViewTests.mm`

**Step 1: Write tests**

```objc
// mac/tests/OpenLyricsViewTests.mm
#import <XCTest/XCTest.h>
#import "OpenLyricsView.h"

@interface OpenLyricsViewTests : XCTestCase
@end

@implementation OpenLyricsViewTests

- (void)testViewCreation {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertNotNil(view);
    XCTAssertTrue(view.wantsLayer);
}

- (void)testViewAcceptsFirstResponder {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue([view acceptsFirstResponder]);
}

@end
```

**Step 2: Run tests to verify they fail**

Run: `bash scripts/run-tests.sh`
Expected: FAIL.

**Step 3: Implement OpenLyricsView.h**

```objc
// mac/OpenLyricsView.h
#pragma once

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

@interface OpenLyricsView : NSView

- (instancetype)initWithFrame:(NSRect)frame;

@end

#endif
```

**Step 4: Implement OpenLyricsView.mm (minimal)**

```objc
// mac/OpenLyricsView.mm
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

@implementation OpenLyricsView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // Background
    CGContextSetRGBFillColor(ctx, 0.1, 0.1, 0.1, 1.0);
    CGContextFillRect(ctx, dirtyRect);

    // Placeholder text
    NSString *text = @"OpenLyrics -- No lyrics loaded";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };

    NSSize textSize = [text sizeWithAttributes:attrs];
    NSPoint point = NSMakePoint(
        (NSWidth(self.bounds) - textSize.width) / 2.0,
        (NSHeight(self.bounds) - textSize.height) / 2.0
    );
    [text drawAtPoint:point withAttributes:attrs];
}

@end
```

**Step 5: Update OpenLyricsRegistration.mm**

Add the NSViewController wrapper and ui_element_mac registration, following the reference project pattern exactly. See design doc section "Component Registration" for the full code.

**Step 6: Run tests**

Run: `bash scripts/run-tests.sh`
Expected: All tests pass.

**Step 7: Deploy and verify**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Component loads in foobar2000. "OpenLyrics Panel" appears in layout options. Adding it shows a dark panel with "No lyrics loaded" centered text.

**Step 8: Commit**

```bash
git add mac/OpenLyricsView.h mac/OpenLyricsView.mm mac/OpenLyricsRegistration.mm mac/tests/OpenLyricsViewTests.mm
git commit -m "Add minimal OpenLyricsView panel with static text display"
```

---

## Layer 4: Lyric Sources + Search Pipeline

### Task 4.1: Wire up playback callbacks and lyric search

**Files:**
- Modify: `mac/OpenLyricsRegistration.mm` (add play_callback_static)
- Modify: `mac/OpenLyricsView.h` (add lyric data members)
- Modify: `mac/OpenLyricsView.mm` (respond to track changes, trigger search, display results)

**Step 1: Add playback callbacks**

In `OpenLyricsRegistration.mm`, add a `play_callback_static` subclass (same pattern as reference project's `playback_state_callback`) that detects:
- `on_playback_new_track` -- trigger lyric search
- `on_playback_stop` -- clear lyrics
- `on_playback_seek` -- update scroll position
- `on_playback_pause` -- pause/resume scroll timer

Post `NSNotification` from callbacks so `OpenLyricsView` instances can observe.

**Step 2: Add lyric storage to OpenLyricsView**

Add ivars/properties for:
- `LyricData m_lyrics` (from `src/lyric_data.h`)
- `metadb_handle_ptr m_now_playing`
- `metadb_v2_rec_t m_now_playing_info`

**Step 3: Connect to lyric search**

On `on_playback_new_track`, call the existing `lyric_search` functions from `src/lyric_search.h`. The search infrastructure uses the existing source registry, HTTP layer, and parsers -- all compiled in Layer 2.

Wire `announce_lyric_update` (from `src/lyric_io.h`) to post an NSNotification that OpenLyricsView observes to update its displayed lyrics.

**Step 4: Display fetched lyrics**

Update `drawRect:` to render actual lyric lines when `m_lyrics` has data. For now, just render each line as a separate `NSAttributedString` drawn at successive Y positions. Full scrolling comes in Layer 5.

**Step 5: Deploy and verify**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Play a track with local lyric files or ID3 tags. Lyrics appear in the panel as static text.

**Step 6: Commit**

```bash
git add -A
git commit -m "Wire up playback callbacks and lyric search pipeline"
```

---

### Task 4.2: Verify internet sources work

**Step 1: Enable internet sources in source config**

Ensure the default source configuration includes at least lrclib (the simplest internet source). The defaults come from the upstream `preferences.h` / source config code compiled in Layer 2.

**Step 2: Test with a track that has no local lyrics**

Play a well-known track. Verify that:
- The search triggers and hits lrclib
- Lyrics are returned and displayed
- The HTTP request completes (libcurl working correctly)

**Step 3: Test multiple sources**

Enable additional sources and verify each returns results. Check logging output for any errors.

**Step 4: Commit if any fixes needed**

```bash
git add -A
git commit -m "Fix internet source integration issues"
```

---

## Layer 5: Synced Scrolling + Unsynced Display

### Task 5.1: Implement Core Text lyric rendering

**Files:**
- Modify: `mac/OpenLyricsView.h` (add rendering state)
- Modify: `mac/OpenLyricsView.mm` (full drawRect: implementation)

**Step 1: Implement three rendering states**

Replace the placeholder `drawRect:` with the full rendering pipeline:

1. **No lyrics**: centered message text (matching upstream's different messages based on reason -- instrumental, search failed, no search yet)
2. **Unsynced lyrics**: render all lines with word wrap, vertically positioned per text alignment preference
3. **Synced lyrics**: render all lines with current line highlighted, scroll position based on playback time

Use Core Text for text layout:
- `CTFramesetterCreateWithAttributedString` for word-wrapped text
- Per-line positioning computed from font metrics + line gap preference
- Colors from preferences: main text, highlight, past-text

**Step 2: Add NSTimer for smooth scrolling**

Create an NSTimer that fires at ~60 Hz (matching upstream's timer approach):
- Started on playback start, stopped on pause/stop
- Each tick: query current playback time, compute target scroll position, interpolate, call `setNeedsDisplay:`
- Scroll interpolation using upstream's `scroll_time_seconds` preference

**Step 3: Implement manual scroll**

Handle `scrollWheel:`, `mouseDown:`, `mouseDragged:`, `mouseUp:` to apply manual scroll offset (same logic as upstream's `OnMouseWheel` / `OnLMBDown` / `OnLMBUp`).

**Step 4: Deploy and verify**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Synced lyrics scroll smoothly. Current line highlighted. Unsynced lyrics display correctly. Mouse wheel adjusts scroll.

**Step 5: Commit**

```bash
git add -A
git commit -m "Implement Core Text lyric rendering with synced scrolling"
```

---

## Layer 6: Context Menu

### Task 6.1: Implement context menu

**Files:**
- Create: `mac/OpenLyricsContextMenu.mm`
- Modify: `mac/OpenLyricsView.mm` (add menuForEvent:)

**Step 1: Build NSMenu programmatically**

Implement `menuForEvent:` on OpenLyricsView. Build an NSMenu with all upstream context menu items:
- Search for lyrics
- Search for lyrics (manual)
- Edit lyrics
- Auto-edits submenu (all AutoEditType values)
- Save lyrics
- Open file location
- Mark as instrumental
- Show lyric info
- Refresh

Each menu item's action calls the corresponding upstream function from the shared code.

**Step 2: Wire up "Open file location"**

On macOS, replace `ShellExecute` with `[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""]`.

**Step 3: Deploy and verify**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Right-click shows context menu. All items trigger correct actions.

**Step 4: Commit**

```bash
git add -A
git commit -m "Add context menu with all upstream actions"
```

---

## Layer 7: Lyric Editor

### Task 7.1: Implement lyric editor

**Files:**
- Create: `mac/OpenLyricsEditor.h`
- Create: `mac/OpenLyricsEditor.mm`
- Create: `mac/tests/OpenLyricsEditorTests.mm`

**Step 1: Write tests**

```objc
// mac/tests/OpenLyricsEditorTests.mm
#import <XCTest/XCTest.h>
#import "OpenLyricsEditor.h"

@interface OpenLyricsEditorTests : XCTestCase
@end

@implementation OpenLyricsEditorTests

- (void)testEditorCreation {
    OpenLyricsEditor *editor = [[OpenLyricsEditor alloc] init];
    XCTAssertNotNil(editor);
    XCTAssertNotNil(editor.window);
}

- (void)testEditorHasTextView {
    OpenLyricsEditor *editor = [[OpenLyricsEditor alloc] init];
    // Editor should contain an NSTextView for lyric editing
    XCTAssertNotNil(editor.textView);
}

@end
```

**Step 2: Implement OpenLyricsEditor**

NSPanel built programmatically:
- `NSTextView` (scrollable) for lyric text
- Toolbar row: Back 5s, Forward 5s, Play/Pause, Line Sync, Reset, Apply Offset, Sync Offset (all NSButton)
- Bottom row: Cancel, Apply, OK
- Receives current lyric text and track info on init
- Playback controls use `static_api_ptr_t<playback_control>` (same as upstream)
- Line sync: inserts timestamp `[mm:ss.xx]` at cursor position using current playback time
- Apply/OK: parse edited text back through LRC parser, save via `lyric_io`

All UI built in code (no XIB). Follow NSPanel patterns -- sheet or floating window attached to foobar2000's main window.

**Step 3: Connect to context menu**

Wire the "Edit lyrics" context menu item to open the editor.

**Step 4: Run tests**

Run: `bash scripts/run-tests.sh`
Expected: Editor tests pass.

**Step 5: Deploy and verify**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: "Edit lyrics" opens editor. Text editing works. Line sync inserts timestamps. OK saves and updates display.

**Step 6: Commit**

```bash
git add -A
git commit -m "Add lyric editor with timestamp sync support"
```

---

## Layer 8: Manual Search + Bulk Search

### Task 8.1: Implement manual search dialog

**Files:**
- Create: `mac/OpenLyricsManualSearch.h`
- Create: `mac/OpenLyricsManualSearch.mm`

**Step 1: Build NSPanel programmatically**

- Text fields: Artist, Album, Title (pre-filled from current track metadata)
- Search button
- NSTableView with columns: Source, Artist, Album, Title, Timestamped
- Column sorting via NSSortDescriptor on column header click
- Double-click or Apply button applies selected result
- Cancel button closes

**Step 2: Connect to search infrastructure**

Search button triggers `lyric_search` manual search functions from shared code. Results populate the table view. Sources are queried in parallel (upstream behavior preserved).

**Step 3: Deploy and verify**

Expected: "Search for lyrics (manual)" opens dialog. Search returns results from all enabled sources. Applying a result updates the panel.

**Step 4: Commit**

```bash
git add -A
git commit -m "Add manual lyric search dialog"
```

---

### Task 8.2: Implement bulk search

**Files:**
- Create: `mac/OpenLyricsBulkSearch.h`
- Create: `mac/OpenLyricsBulkSearch.mm`

**Step 1: Build NSPanel programmatically**

- NSProgressIndicator (determinate, showing progress through selected tracks)
- Status label showing current track being searched
- Cancel button
- Launched from playlist context menu (see Task 8.3)

**Step 2: Connect to search infrastructure**

Run searches on a background dispatch queue. Post progress updates to main thread. Respect upstream's anti-flood delay between internet source requests. Add to existing search queue (upstream behavior).

**Step 3: Commit**

```bash
git add -A
git commit -m "Add bulk lyric search with progress tracking"
```

---

### Task 8.3: Implement playlist context menu items

**Files:**
- Create: `mac/OpenLyricsPlaylistContextMenu.mm`

Upstream registers context menu items in the playlist right-click menu:
- OpenLyrics > Search for lyrics
- OpenLyrics > Search manually
- OpenLyrics > Edit lyrics
- OpenLyrics > Mark as instrumental
- OpenLyrics > Bulk search

Use the foobar2000 SDK `contextmenu_item_simple` to register these. The implementation calls into the same shared code as the panel context menu.

**Step 1: Implement and register**

**Step 2: Commit**

```bash
git add -A
git commit -m "Add playlist context menu items for OpenLyrics"
```

---

## Layer 9: Preferences UI

### Task 9.1: Implement preferences pages

**Files:**
- Create: `mac/OpenLyricsPreferences.h`
- Create: `mac/OpenLyricsPreferences.mm`

**Step 1: Implement root preferences page**

NSViewController registered with foobar2000's macOS preferences system. Shows a label pointing to sub-pages (matching upstream's root page).

**Step 2: Implement sub-pages one at a time**

Each sub-page is an NSViewController with programmatic UI:

1. **Searching** -- NSTableView with checkboxes for active sources, NSButton for exclude trailing brackets, NSTextField for skip filter, NSPopUpButton for preferred lyric type, NSButton for search-without-panels
2. **Search sources** -- Per-source config (NSTextField for Musixmatch API key, etc.)
3. **Saving** -- NSPopUpButton for auto-save strategy and save source, NSTextField for filename format and tag names, NSButton for LRC merge
4. **Display** -- NSButton to open NSFontPanel, NSColorWell for text/highlight/past colors, NSPopUpButton for scroll type and alignment, NSTextField for scroll time and line gap, NSButton for debug logs
5. **Background** -- NSPopUpButton for fill type and image type, NSSlider for opacity and blur radius, NSColorWell for gradient corners, file picker for custom image
6. **Editing** -- NSTableView with checkboxes for auto-edit types
7. **Upload** -- NSPopUpButton for LRCLIB upload strategy

All controls bind to the corresponding `cfg_bool` / `cfg_int` / `cfg_string` variables. Changes take effect immediately (matching upstream's `on_change` callbacks).

**Step 3: Deploy and verify each page**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: All preferences pages accessible. Changing settings persists across restarts. Settings affect panel behavior (font, colors, sources, etc.).

**Step 4: Commit (one per sub-page or batch)**

```bash
git add -A
git commit -m "Add preferences UI with all configuration pages"
```

---

## Layer 10: Background Images

### Task 10.1: Implement ImageProcessing.mm

**Files:**
- Create: `mac/ImageProcessing.mm`
- Create: `mac/tests/ImageProcessingTests.mm`

**Step 1: Write tests**

```objc
// mac/tests/ImageProcessingTests.mm
#import <XCTest/XCTest.h>
#include "img_processing.h"

@interface ImageProcessingTests : XCTestCase
@end

@implementation ImageProcessingTests

- (void)testGenerateSolidBackground {
    RGBAColour colour = {255, 0, 0, 255};
    Image img = generate_background_colour(100, 100, colour);
    XCTAssertTrue(img.valid());
    XCTAssertEqual(img.width, 100);
    XCTAssertEqual(img.height, 100);
    // First pixel should be red
    XCTAssertEqual(img.pixels[0], 255);
    XCTAssertEqual(img.pixels[1], 0);
    XCTAssertEqual(img.pixels[2], 0);
}

- (void)testResizeImage {
    RGBAColour colour = {128, 128, 128, 255};
    Image img = generate_background_colour(200, 200, colour);
    Image resized = resize_image(img, 100, 100);
    XCTAssertTrue(resized.valid());
    XCTAssertEqual(resized.width, 100);
    XCTAssertEqual(resized.height, 100);
}

- (void)testBlurImage {
    RGBAColour colour = {128, 128, 128, 255};
    Image img = generate_background_colour(200, 200, colour);
    Image blurred = blur_image(img, 5);
    XCTAssertTrue(blurred.valid());
    XCTAssertEqual(blurred.width, 200);
    XCTAssertEqual(blurred.height, 200);
}

@end
```

**Step 2: Implement macOS image functions**

```objc
// mac/ImageProcessing.mm
// Provides macOS implementations of:
// - load_image(const char* file_path)
// - decode_image(const void* buffer, size_t length)
// - resize_image(const Image& input, int width, int height)
// - blur_image(const Image& input, int radius)

// load_image / decode_image: use CGImageSource (ImageIO framework)
// resize_image: CGBitmapContext + CGContextDrawImage with high-quality interpolation
// blur_image: vImageBoxConvolve_ARGB8888 (3-pass, same algorithm as upstream)
```

Implement each function using Core Graphics and vImage. The pure-math functions (`generate_background_colour`, `lerp_colour`, `lerp_image`, `transpose_image`) are compiled from `src/img_processing.cpp` -- only include the platform-independent parts. The Windows-only parts (WIC, SSE SIMD blur) are excluded via `#ifdef`.

**Step 3: Run tests**

Run: `bash scripts/run-tests.sh`
Expected: All image processing tests pass.

**Step 4: Commit**

```bash
git add -A
git commit -m "Add macOS image processing with Core Graphics and vImage blur"
```

---

### Task 10.2: Wire up background rendering in OpenLyricsView

**Files:**
- Modify: `mac/OpenLyricsView.mm` (add background image compositing to drawRect:)
- Modify: `mac/OpenLyricsRegistration.mm` (add album art notification handling)

**Step 1: Add album art retrieval**

Register for `now_playing_album_art_notify` callbacks. On new art data, decode with `decode_image()`, store in view.

**Step 2: Add background rendering to drawRect:**

Before drawing text, render the background:
1. Solid color or gradient (from preferences)
2. If image background enabled: resize to panel size, apply blur, draw with opacity
3. Composite all layers

**Step 3: Deploy and verify**

Expected: Album art backgrounds show behind lyrics. Gradient backgrounds work. Custom image path works. Blur and opacity preferences affect rendering.

**Step 4: Commit**

```bash
git add -A
git commit -m "Add background image rendering with album art, blur, and gradients"
```

---

## Layer 11: External Window

### Task 11.1: Implement external lyrics window

**Files:**
- Create: `mac/OpenLyricsExternalWindow.h`
- Create: `mac/OpenLyricsExternalWindow.mm`

**Step 1: Implement NSPanel subclass**

A floating utility window (`NSPanel` with `NSWindowStyleMaskUtilityWindow`) containing an OpenLyricsView. Shares the same rendering code as the embedded panel.

Features:
- Resizable
- Always-on-top option
- Remembers position and size across sessions (via cfg_ variables)
- Opaque background option (from preferences)
- Closeable via window close button or menu

**Step 2: Wire up to context menu or menu bar**

Add "Show external window" to the panel context menu.

**Step 3: Deploy and verify**

Expected: External window opens, shows lyrics, scrolls in sync. Resizing works. Closing and reopening preserves state.

**Step 4: Commit**

```bash
git add -A
git commit -m "Add external floating lyrics window"
```

---

## Layer 12: CI + Polish

### Task 12.1: Add GitHub Actions CI

**Files:**
- Create: `.github/workflows/build_and_test.yml`

**Step 1: Create workflow**

```yaml
name: Build and Test
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-13
    steps:
      - uses: actions/checkout@v4
      - name: Build dependencies
        run: bash scripts/build-deps.sh
      - name: Build component
        run: xcodebuild -project mac/openlyrics.xcodeproj -configuration Release -arch x86_64 -arch arm64 build
      - name: Run tests
        run: bash scripts/run-tests.sh
```

Note: The CI job will need the foobar2000 SDK available. Determine whether it can be downloaded in CI or needs to be vendored/cached.

**Step 2: Commit**

```bash
git add .github/workflows/build_and_test.yml
git commit -m "Add GitHub Actions CI for build and test"
```

---

### Task 12.2: Final polish and verification

**Step 1: Run full test suite**

Run: `bash scripts/run-tests.sh`
Expected: All tests pass (both XCTest and mvtf).

**Step 2: Full deploy test**

Run: `bash scripts/deploy-component.sh --build`
Expected: Clean build, all tests pass, component installs, foobar2000 launches with working OpenLyrics panel.

**Step 3: Feature verification checklist**

- [ ] Panel displays in foobar2000 layout
- [ ] Unsynced lyrics display correctly
- [ ] Synced lyrics scroll smoothly
- [ ] Manual scroll (wheel + drag) works
- [ ] All internet sources return results
- [ ] Local file and ID3 tag sources work
- [ ] Context menu shows all items
- [ ] Editor opens, edits, and saves
- [ ] Line sync in editor works
- [ ] Manual search dialog works
- [ ] Bulk search works
- [ ] All preferences pages load and save
- [ ] Font and color changes take effect
- [ ] Background images (album art, custom, gradient) render
- [ ] Blur and opacity work
- [ ] External window works
- [ ] Auto-edits apply correctly
- [ ] Search avoidance works
- [ ] Dark mode works throughout
- [ ] Component survives foobar2000 restart

**Step 4: Update CLAUDE.md and README**

Ensure all build instructions are current. Add any discovered caveats.

**Step 5: Commit**

```bash
git add -A
git commit -m "Final polish and verification"
```
