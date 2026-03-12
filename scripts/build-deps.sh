#!/bin/bash
# Build script for foo_openlyrics macOS dependencies.
#
# The foobar2000 SDK is expected at deps/foobar2000-sdk/ (typically a symlink
# to the sibling foo_vis_projectM project).  Only libcurl is built locally.
#
# Usage:
#   bash scripts/build-deps.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="$PROJECT_DIR/deps"
ARCHS=(x86_64 arm64)

echo "Building dependencies for ${ARCHS[*]}..."

# ── Resolve foobar2000 SDK ────────────────────────────────────────────────────

SDK="$DEPS_DIR/foobar2000-sdk"

if [ ! -d "$SDK" ]; then
    echo "ERROR: deps/foobar2000-sdk/ not found."
    echo "Symlink it from the sibling project:"
    echo "  mkdir -p deps && ln -s ../../foo_vis_projectM/deps/foobar2000-sdk deps/foobar2000-sdk"
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

# ── Build foobar2000 SDK static libraries ─────────────────────────────────────

echo ""
echo "=== Building foobar2000 SDK ==="

SDK_PROJECTS=(
    "$SDK/pfc/pfc.xcodeproj"
    "$SDK/foobar2000/SDK/foobar2000_SDK.xcodeproj"
    "$SDK/foobar2000/helpers/foobar2000_SDK_helpers.xcodeproj"
    "$SDK/foobar2000/foobar2000_component_client/foobar2000_component_client.xcodeproj"
    "$SDK/foobar2000/shared/shared.xcodeproj"
)
SDK_LIBS=(
    "$SDK/pfc/build/Release/libpfc-Mac.a"
    "$SDK/foobar2000/SDK/build/Release/libfoobar2000_SDK.a"
    "$SDK/foobar2000/helpers/build/Release/libfoobar2000_SDK_helpers.a"
    "$SDK/foobar2000/foobar2000_component_client/build/Release/libfoobar2000_component_client.a"
    "$SDK/foobar2000/shared/build/Release/libshared.a"
)

for i in "${!SDK_PROJECTS[@]}"; do
    proj="${SDK_PROJECTS[$i]}"
    lib="${SDK_LIBS[$i]}"
    name="$(basename "$proj" .xcodeproj)"
    if [ -f "$lib" ] && has_all_arches "$lib"; then
        echo "  $name already built, skipping."
    else
        echo "  Building $name..."
        xcodebuild -project "$proj" -configuration Release -arch x86_64 -arch arm64 build -quiet
    fi
done

echo "SDK libraries built."

# ── Build libcurl as a universal static lib with SecureTransport ──────────────

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

    CURL_TMPDIR="$(mktemp -d)"
    CURL_TARBALL="$CURL_TMPDIR/curl-${CURL_VERSION}.tar.gz"
    CURL_SRC="$CURL_TMPDIR/curl-${CURL_VERSION}"

    echo "  Downloading curl ${CURL_VERSION}..."
    curl -L --silent --show-error -o "$CURL_TARBALL" "$CURL_URL"

    echo "  Extracting..."
    tar -xzf "$CURL_TARBALL" -C "$CURL_TMPDIR"

    SLICE_LIBS=()
    for arch in "${ARCHS[@]}"; do
        echo "  Configuring for $arch..."
        BUILD_DIR="$CURL_TMPDIR/build-$arch"
        mkdir -p "$BUILD_DIR"

        (cd "$CURL_SRC" && make distclean > /dev/null || true)

        (cd "$CURL_SRC" && \
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
            > /dev/null)

        echo "  Building for $arch..."
        (cd "$CURL_SRC" && make -j"$(sysctl -n hw.ncpu)" > /dev/null)
        (cd "$CURL_SRC" && make install > /dev/null)

        SLICE_LIBS+=("$BUILD_DIR/install/lib/libcurl.a")
    done

    cd "$PROJECT_DIR"

    echo "  Creating universal binary..."
    lipo -create "${SLICE_LIBS[@]}" -output "$CURL_LIB"

    # Copy headers from the last built arch (they are arch-independent)
    if [ ! -d "$CURL_DIR/include/curl" ]; then
        cp -R "${CURL_TMPDIR}/build-${ARCHS[${#ARCHS[@]}-1]}/install/include/curl" "$CURL_DIR/include/"
    fi

    rm -rf "$CURL_TMPDIR"
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
