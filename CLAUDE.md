# CLAUDE.md

## Project Goal

macOS port of [foo_openlyrics](https://github.com/jacquesh/foo_openlyrics), a foobar2000 lyrics plugin. The upstream Windows version uses Win32/ATL/WTL/GDI throughout. This port replaces all platform-specific code with Cocoa/AppKit equivalents while preserving full feature parity.

- License: MIT (matching upstream)
- Upstream version baseline: v1.13

## Architecture

```
foobar2000 (macOS)
    |
    +-- play_callback / metadb callbacks (lyrics search triggers)
    |
    v
foo_openlyrics.component (macOS bundle, statically linked)
    |
    +-- OpenLyricsView : NSView (lyrics display panel)
    |       +-- Core Text rendering (synced scrolling, unsynced, no-lyrics states)
    |       +-- Background images (album art, custom, gradients, blur)
    |       +-- Context menu (NSMenu)
    |
    +-- OpenLyricsRegistration.mm (cfg globals, ui_element_mac registration)
    +-- Lyric sources (local files, ID3 tags, 15 internet sources)
    +-- LRC parser
    +-- Lyric editor (NSWindow/NSPanel)
    +-- Manual search (NSWindow)
    +-- Bulk search
    +-- Preferences pages
    +-- Auto-edits
    +-- HTTP via libcurl (static)
    +-- Image processing via Core Graphics / vImage
```

## Reference Project

`/Users/gabito/Sites/foo_vis_projectM` is a working macOS foobar2000 component. Use it as reference for:
- `ui_element_mac` registration pattern
- Xcode project structure (.component bundle)
- Build scripts (build-deps.sh, deploy-component.sh, run-tests.sh)
- stdafx.h setup (foobar2000+atl.h + Cocoa/Cocoa.h)
- Static linking of foobar2000 SDK libs
- pfc::myassert stub

## Build Commands

```bash
# First time: build all deps + component + deploy to foobar2000
bash scripts/deploy-component.sh --build

# Rebuild deps only (needed if deps/foobar2000-sdk/ or deps/curl/ is missing)
bash scripts/build-deps.sh

# Rebuild component only (if deps already built), then deploy
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build

# Deploy already-built component without rebuilding
bash scripts/deploy-component.sh

# Run XCTest suite only
bash scripts/run-tests.sh
```

The deploy script closes foobar2000 if it is running, runs `scripts/run-tests.sh`, copies the component to `~/Library/foobar2000-v2/user-components/foo_openlyrics/`, verifies binary UUIDs, and launches foobar2000.

Always run `bash scripts/deploy-component.sh` (or with `--build`) after implementing new features, bug fixes, or other behavior changes.

## Key Files

| File | Purpose |
|------|---------|
| `mac/OpenLyricsView.h` | Shared interface for the lyrics display NSView |
| `mac/OpenLyricsView.mm` | Core rendering: Core Text layout, scrolling, backgrounds |
| `mac/OpenLyricsRegistration.mm` | Component metadata, cfg globals, ui_element_mac registration |
| `mac/stdafx.h` | Precompiled header: foobar2000 SDK + Cocoa imports |
| `mac/openlyrics.xcodeproj` | Xcode project |
| `src/` | Shared and platform-specific source (lyric data, parsers, sources, search, IO) |
| `scripts/build-deps.sh` | Builds foobar2000 SDK static libs + libcurl |
| `scripts/deploy-component.sh` | Build, test, install to foobar2000 |
| `scripts/run-tests.sh` | Runs XCTest target |

## Dependencies

All statically linked:
- **foobar2000 SDK**: `deps/foobar2000-sdk/` (pfc, SDK, helpers, component_client, shared)
- **libcurl**: for HTTP requests (upstream uses curl too)
- **pugixml**: XML/HTML parsing (already in 3rdparty/)
- **tidy-html5**: HTML cleanup (already in 3rdparty/)
- **cJSON**: JSON parsing (already in 3rdparty/)

## Platform Mapping

| Windows (upstream) | macOS (this port) |
|---|---|
| CWindowImpl / ATL message maps | NSView subclass |
| GDI HDC text rendering | Core Text + CGContext |
| Win32 timers (SetTimer) | NSTimer or CVDisplayLink |
| HBITMAP back buffer | CGBitmapContext / CALayer |
| CDialogImpl (editor, search) | NSWindow / NSPanel |
| WIC image codecs | CGImage / NSImage |
| COLORREF | NSColor / CGColor |
| CRect / CPoint / CSize | NSRect / NSPoint / NSSize |
| TCHAR / wchar_t | UTF-8 std::string / NSString |
| libPPUI preferences | NSViewController-based preferences |
| ColumnsUI SDK | Not applicable on macOS |
| SSE SIMD (blur) | NEON intrinsics or vImage framework |

## Repository Constraints

- Do not modify anything under `deps/` (once created).
- Do not modify upstream source files in `src/` that can be used as-is. When platform adaptation is needed, use `#ifdef __APPLE__` or separate mac/ files.
- Source code in English.

## Key Implementation Details

- **foobar2000 bridging**: `fb2k::wrapNSObject()` / `unwrapNSObject()` from `commonObjects-Apple.h`; `instantiate()` returns wrapped `NSViewController`.
- **pfc assert stub**: `namespace pfc { void myassert(...) {} }` required because SDK libs are Release but component may build with debug flags.
- **OpenGL deprecation**: suppressed via `#pragma clang diagnostic ignored "-Wdeprecated-declarations"` if needed.
- **Hardened runtime**: all deps must be static libs to avoid `SIGKILL (Code Signature Invalid)`.
- **announce_lyric_update** (`mac/OpenLyricsView.mm`): must call `io::process_available_lyric_update()` on the main thread before displaying — this applies automated auto-edits (HTML entity decoding, etc.) and saves lyrics. Passing raw `update.lyrics` directly to the view bypasses all auto-edits.
- **Word wrap** (`OpenLyricsView.mm` `_buildLineCache:`): uses `CTTypesetterSuggestLineBreak` to split each lyric line into multiple visual rows. `_cachedLines` is a flat array of `CTLineRef` (one per visual row); `_lyricLineIndices` maps each row back to its lyric line index for synced colour selection. Cache is rebuilt lazily in `drawRect:` whenever usable width or line height changes.
- **Manual scroll offset** (`_manualScrollDelta`): mirrors Windows `m_manual_scroll_distance` — an offset added on top of the auto-scroll target each tick, not a replacement for it. Scroll events accumulate into `_manualScrollDelta`; `_updateScrollPosition` lerps `_scrollOffset` toward `_targetScrollOffset + _manualScrollDelta`. Reset to 0 on new track.
- **Unicode normalisation** (`mac/PlatformUtil.mm`): use NFKD (`decomposedStringWithCompatibilityMapping`), not NFC. NFKD decomposes "ó" → ASCII 'o' + combining accent, which is required for correct URL slug generation in web-scraping lyric sources.
- **Encoding detection** (`src/lyric_io.cpp` macOS path): validate UTF-8 before accepting; detect UTF-16 via BOM (FF FE / FE FF) and convert; fall back to Latin-1 (ISO-8859-1) for older LRC files saved by Windows tools.
