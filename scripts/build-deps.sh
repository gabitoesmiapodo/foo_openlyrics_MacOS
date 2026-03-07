#!/bin/bash
# Build script for foo_openlyrics macOS dependencies.
#
# Prerequisites:
#   The foobar2000 SDK must be placed at deps/foobar2000-sdk/ before running.
#   You can copy it from the reference project:
#     cp -R /path/to/foo_vis_projectM/deps/foobar2000-sdk/ deps/foobar2000-sdk/
#
# Usage:
#   bash scripts/build-deps.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="$PROJECT_DIR/deps"
ARCHS=(x86_64 arm64)

echo "Building dependencies for ${ARCHS[*]}..."

if [ ! -d "$DEPS_DIR/foobar2000-sdk" ]; then
    echo "ERROR: deps/foobar2000-sdk/ not found."
    echo "Copy it from a reference project first:"
    echo "  cp -R /path/to/foo_vis_projectM/deps/foobar2000-sdk/ deps/foobar2000-sdk/"
    exit 1
fi

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

# 2. Build libcurl as a universal static lib with SecureTransport
echo ""
echo "=== Building libcurl ==="
CURL_DIR="$DEPS_DIR/curl"
CURL_LIB="$CURL_DIR/lib/libcurl.a"
CURL_VERSION="8.5.0"
CURL_URL="https://curl.se/download/curl-${CURL_VERSION}.tar.gz"

mkdir -p "$CURL_DIR/lib" "$CURL_DIR/include"

if [ -f "$CURL_LIB" ] && has_all_arches "$CURL_LIB"; then
    echo "libcurl universal static lib already built, skipping."
else
    rm -f "$CURL_LIB"

    TMPDIR="$(mktemp -d)"
    CURL_TARBALL="$TMPDIR/curl-${CURL_VERSION}.tar.gz"
    CURL_SRC="$TMPDIR/curl-${CURL_VERSION}"

    echo "  Downloading curl ${CURL_VERSION}..."
    curl -L --silent --show-error -o "$CURL_TARBALL" "$CURL_URL"

    echo "  Extracting..."
    tar -xzf "$CURL_TARBALL" -C "$TMPDIR"

    SLICE_LIBS=()
    for arch in "${ARCHS[@]}"; do
        echo "  Configuring for $arch..."
        BUILD_DIR="$TMPDIR/build-$arch"
        mkdir -p "$BUILD_DIR"

        cd "$CURL_SRC"
        make distclean > /dev/null 2>&1 || true

        CFLAGS="-arch $arch -mmacosx-version-min=13.0 -O2" \
        ./configure \
            --host="${arch}-apple-darwin" \
            --prefix="$BUILD_DIR/install" \
            --disable-shared \
            --enable-static \
            --with-secure-transport \
            --disable-ldap \
            --disable-ldaps \
            --disable-rtsp \
            --disable-dict \
            --disable-telnet \
            --disable-tftp \
            --disable-pop3 \
            --disable-imap \
            --disable-smb \
            --disable-smtp \
            --disable-gopher \
            --disable-mqtt \
            --disable-manual \
            --disable-docs \
            --disable-dependency-tracking \
            --without-libidn2 \
            --without-libpsl \
            --without-brotli \
            --without-zstd \
            --without-nghttp2 \
            > /dev/null 2>&1

        echo "  Building for $arch..."
        make -j"$(sysctl -n hw.ncpu)" > /dev/null 2>&1
        make install > /dev/null 2>&1

        SLICE_LIBS+=("$BUILD_DIR/install/lib/libcurl.a")
    done

    echo "  Creating universal binary..."
    lipo -create "${SLICE_LIBS[@]}" -output "$CURL_LIB"

    # Copy headers from the last built arch (they are arch-independent)
    if [ ! -d "$CURL_DIR/include/curl" ]; then
        cp -R "${TMPDIR}/build-${ARCHS[-1]}/install/include/curl" "$CURL_DIR/include/"
    fi

    rm -rf "$TMPDIR"
    echo "libcurl built and installed to deps/curl/"
fi

echo ""
echo "All dependencies built for ${ARCHS[*]}."
echo ""
echo "SDK static libraries:"
ls "$SDK/pfc/build/Release/"*.a \
   "$SDK/foobar2000/SDK/build/Release/"*.a \
   "$SDK/foobar2000/helpers/build/Release/"*.a \
   "$SDK/foobar2000/foobar2000_component_client/build/Release/"*.a \
   "$SDK/foobar2000/shared/build/Release/"*.a 2>/dev/null
echo ""
echo "curl static library:"
ls "$CURL_DIR/lib/"*.a 2>/dev/null
lipo -archs "$CURL_LIB" 2>/dev/null && echo "  (universal: ${ARCHS[*]})"
