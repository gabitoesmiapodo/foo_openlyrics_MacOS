# foo_openlyrics macOS Port -- Design Document

Date: 2026-03-06
Upstream baseline: v1.13
Scope: Full feature parity

## Goal

Port foo_openlyrics to macOS as a native foobar2000 component. Replace all Win32/ATL/WTL/GDI code with Cocoa/AppKit equivalents. Reuse platform-independent shared logic (parsers, sources, search, auto-edits, lyric data) directly from the upstream `src/` directory.

## Decisions

| Decision | Choice |
|---|---|
| Scope | Full feature parity with upstream v1.13 |
| Code organization | `mac/` for macOS code, `src/` shared/reference, `deps/` for SDK |
| Port strategy | Layer-by-layer bottom-up |
| UI rendering | Core Text + CGContext in NSView `drawRect:` |
| Image blur | vImage (Accelerate framework) |
| Dialogs (editor, search) | Programmatic NSWindow/NSPanel, no XIBs |
| Testing | mvtf for shared logic, XCTest for macOS-specific |
| Preferences | Full UI, NSViewController-based |
| HTTP | libcurl (static, same as upstream) |
| Min macOS version | 13.0 (Ventura) |
| Architecture | Universal binary (x86_64 + arm64) |
| Linking | All static (hardened runtime) |
| Platform shims | Minimal PlatformUtil.h for types shared code needs |
| Build system | Xcode project + shell scripts |

## Directory Layout

```
foo_openlyrics_MacOS/
  src/                    # Upstream source (shared + Windows-specific)
  mac/                    # All macOS-specific code
    openlyrics.xcodeproj/
    stdafx.h              # macOS precompiled header
    OpenLyricsView.h
    OpenLyricsView.mm     # Core Text rendering, scrolling, backgrounds
    OpenLyricsRegistration.mm  # Component metadata, cfg globals, ui_element_mac
    OpenLyricsEditor.mm   # Lyric editor (NSPanel, programmatic UI)
    OpenLyricsManualSearch.mm  # Manual search dialog
    OpenLyricsBulkSearch.mm    # Bulk search
    OpenLyricsPreferences.mm   # Preferences pages
    OpenLyricsExternalWindow.mm
    OpenLyricsContextMenu.mm
    ImageProcessing.mm    # Core Graphics + vImage replacements
    PlatformUtil.h/.mm    # macOS replacements for win32_util
    tests/
      OpenLyricsTests.mm  # XCTest for macOS-specific code
  deps/
    foobar2000-sdk/       # Built by build-deps.sh
  3rdparty/               # Existing: pugixml, tidy-html5, cJSON
  scripts/
    build-deps.sh
    deploy-component.sh
    run-tests.sh
  docs/plans/
```

## Component Registration

Following the reference project (foo_vis_projectM) pattern:

- `DECLARE_COMPONENT_VERSION` macro for component metadata
- `pfc::myassert` stub (SDK libs are Release, component may build with debug flags)
- `NSViewController` subclass wrapping `OpenLyricsView`
- `ui_element_mac` subclass with `FB2K_SERVICE_FACTORY` registration
- `fb2k::wrapNSObject()` to bridge NSViewController to foobar2000

Playback callbacks (`play_callback_static`) detect track changes, seek, pause, stop and trigger lyric search and panel updates. Active panel instances tracked in a static vector, registered on `viewDidMoveToWindow` / `removeFromSuperview`.

## Lyrics Panel Rendering

`OpenLyricsView : NSView` handles three states: no lyrics, unsynced, synced.

### Drawing pipeline

```
drawRect:
  +-- Background
  |     +-- Solid / gradient (CGContext fill / CGGradient)
  |     +-- Album art / custom image (CGImage, resized + vImage blur)
  |     +-- Opacity via CGContextSetAlpha
  +-- Lyrics (Core Text)
        +-- CTFramesetterCreateWithAttributedString
        +-- Per-line positioning from scroll state
        +-- Current line highlight color
        +-- Past-text color for elapsed lines
        +-- Word wrap via CTLine
```

### Scrolling

- Synced: NSTimer at ~60 Hz. Playback time determines target scroll position. Interpolation uses `scroll_time_seconds` and `highlight_fade_seconds` preferences.
- Unsynced: static, vertically aligned per preferences.
- Manual: `scrollWheel:` and mouse drag apply manual offset.

### Back buffer

Layer-backed NSView (`wantsLayer = YES`) eliminates the need for manual double buffering.

### Text layout

- Font from preferences via NSFont
- Colors via NSColor / CGColor
- Alignment via CTParagraphStyle + vertical offset
- Line gap from preferences
- Word wrap: CTFramesetter constrained to view width

## Background Images

- Album art: `now_playing_album_art_notify` callback, decoded via CGImage
- Resize: CGBitmapContext + CGContextDrawImage
- Blur: `vImageBoxConvolve_ARGB8888` (3-pass box blur, same algorithm as upstream)
- Opacity: CGContextSetAlpha
- Gradients: CGGradientCreateWithColors + CGContextDrawLinearGradient

## Editor

`OpenLyricsEditor.mm` -- NSPanel built programmatically.

- NSTextView for lyric text
- NSButton toolbar: Back 5s, Forward 5s, Play/Pause, Line Sync, Reset, Apply Offset, Sync Offset
- Cancel / Apply / OK buttons
- Playback state via `play_callback_impl_base`
- Dark mode: automatic via NSAppearance inheritance

## Manual Search

`OpenLyricsManualSearch.mm` -- NSPanel with:

- Text fields for artist, album, title (pre-filled)
- NSTableView for results (source, artist, album, title, is-timestamped)
- Column sorting via NSSortDescriptor
- Double-click or Apply to accept
- Parallel source queries

## Bulk Search

`OpenLyricsBulkSearch.mm` -- NSPanel with:

- NSProgressIndicator
- Status text
- Cancel button
- Background queue execution

## Preferences

NSViewController subclasses registered as foobar2000 macOS preference pages:

- **Root**: links to sub-pages
- **Searching**: active sources (NSTableView + checkboxes), exclude trailing brackets, skip filter, preferred lyric type
- **Search sources**: per-source config
- **Saving**: auto-save strategy, save source, filename format, tag names, LRC merge
- **Display**: NSFontPanel, NSColorWell for text/highlight/past/background, scroll type, scroll time, alignment, line gap, debug logs
- **Background**: fill type, image type, opacity slider, blur radius slider, custom image picker, gradient color wells
- **Editing**: auto-edit toggles
- **Upload**: LRCLIB upload strategy

All backed by cfg_bool / cfg_int / cfg_string persistent settings.

## External Window

NSPanel (floating utility window) containing an OpenLyricsView instance. Shares the same rendering code. Differs in window chrome: title bar, resize, always-on-top behavior.

## Platform Shims (PlatformUtil.h)

Minimal type compatibility for shared source files:

```cpp
using COLORREF = uint32_t;
struct CPoint { int x; int y; };
struct CSize { int cx; int cy; };
struct CRect { int left, top, right, bottom; int Width(); int Height(); };
using TCHAR = char;
using tstring = std::string;
using tstring_view = std::string_view;

std::string to_tstring(std::string_view s);   // identity
std::string from_tstring(std::string_view s);  // identity
bool is_char_whitespace(char c);
```

### img_processing adaptation

- Header: guard `from_colorref` and `toggle_image_rgba_bgra_inplace` with `#ifdef`
- `ImageProcessing.mm`: macOS implementations of `load_image`, `decode_image`, `resize_image`, `blur_image` using Core Graphics + vImage
- Pure-math functions (lerp_colour, generate_background_colour, lerp_image) reused as-is

### Shared source compilation

Source files from `src/` added to Xcode project directly. They compile against the macOS stdafx.h. Minor `#ifdef __APPLE__` only where unavoidable.

### Conditional compilation

Files not included in Xcode project (no `#ifdef` needed):
- `ui_lyrics_panel.cpp/h`
- `ui_lyric_editor.cpp`
- `ui_lyric_manual_search.cpp`
- `ui_lyric_bulk_search.cpp`
- `ui_lyrics_externalwindow.cpp`
- `ui_lyrics_uielement.cpp`
- `ui_contextmenu.cpp`
- `ui_util.cpp/h`
- `win32_util.cpp/h`
- `uie_shim_panel.h`
- `PCH.cpp`
- `foo_openlyrics.rc`

## Testing

### Tier 1: mvtf (shared logic)

Existing upstream tests, guarded by `#if MVTF_TESTS_ENABLED`. Cover LRC parsing, auto-edits, string splitting, changelog validation, hash utils, search avoidance. Run via component load with test build configuration.

### Tier 2: XCTest (macOS-specific)

`mac/tests/OpenLyricsTests.mm`:
- Component registration
- OpenLyricsView lifecycle
- Core Text rendering (attributed string construction, line positioning)
- Platform shim correctness
- Image processing (vImage blur, decode, resize)
- Preferences binding round-trip
- Context menu construction
- Editor/search dialog creation and teardown

Run via `bash scripts/run-tests.sh`.

### CI

GitHub Actions: macOS 13+ runner, build deps, build component, run both test tiers.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/build-deps.sh` | Build foobar2000 SDK static libs + libcurl (universal x86_64/arm64) |
| `scripts/run-tests.sh` | `xcodebuild test` on the test scheme |
| `scripts/deploy-component.sh` | Close foobar2000, optionally build (`--build`), run tests, copy `.component` to `~/Library/foobar2000-v2/user-components/foo_openlyrics/`, verify UUIDs, launch foobar2000 |

### Development workflow

```bash
# First time: build all deps + component + deploy
bash scripts/deploy-component.sh --build

# Rebuild component only (most common)
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build

# Deploy already-built without rebuilding
bash scripts/deploy-component.sh

# Run tests only
bash scripts/run-tests.sh
```

The deploy script always runs tests before installing.

## Implementation Layers (build order)

1. Build system + SDK + Xcode project skeleton
2. Shared source compilation (stdafx.h + PlatformUtil + get `src/` files building)
3. Minimal panel (OpenLyricsView + registration, display static text)
4. Lyric sources + search pipeline (local files, tags, internet sources)
5. Synced scrolling + unsynced display
6. Context menu
7. Editor
8. Manual search + bulk search
9. Preferences UI
10. Background images (album art, custom, gradients, blur)
11. External window
12. CI + polish

## Reference Project

`/Users/gabito/Sites/foo_vis_projectM` -- working macOS foobar2000 component. Used as reference for registration pattern, Xcode project structure, build scripts, stdafx.h, static linking, deploy workflow.
