// mac/OpenLyricsView.mm
#import "stdafx.h"
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

#include "../src/img_processing.h"
#include "../src/lyric_io.h"
#include "../src/lyric_search.h"
#include "../src/metadb_index_search_avoidance.h"
#include "../src/preferences.h"
#include "../src/tag_util.h"
#include "../src/ui_hooks.h"

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------

// SpawnLyricEditorMac is defined in OpenLyricsEditor.mm.
void SpawnLyricEditorMac();
// SpawnManualSearchMac is defined in OpenLyricsManualSearch.mm.
void SpawnManualSearchMac();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

static const CGFloat kFontSize      = 18.0;
static const CGFloat kScrollLerp    = 0.12; // fraction toward target per tick (~60 Hz)
static const CGFloat kTopPadding    = 20.0;
static const CGFloat kSidePadding   = 20.0;

// Fallback colors used when services aren't available (tests / pre-init)
static const CGFloat kColorNormal[4]    = { 1.0, 1.0, 1.0, 1.0 };
static const CGFloat kColorHighlight[4] = { 1.0, 0.85, 0.0, 1.0 };
static const CGFloat kColorPast[4]      = { 0.5, 0.5, 0.5, 1.0 };
static const CGFloat kColorDim[4]       = { 0.55, 0.55, 0.55, 1.0 };
static const CGFloat kColorBackground[4]= { 0.102, 0.102, 0.102, 1.0 }; // #1A1A1A

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

// COLORREF on macOS is 0x00BBGGRR (same as Windows GetRValue/GetGValue/GetBValue).
static inline void colorref_to_cgfloat(t_ui_color c, CGFloat out[4]) {
    out[0] = GetRValue(c) / 255.0;
    out[1] = GetGValue(c) / 255.0;
    out[2] = GetBValue(c) / 255.0;
    out[3] = 1.0;
}

// ---------------------------------------------------------------------------
// Active panel registry (weak references via CF)
// ---------------------------------------------------------------------------

static CFMutableArrayRef g_active_panels_cf;
static dispatch_queue_t  g_panels_queue;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static double get_playback_time() {
    auto pc = play_control::get();
    if (!pc.is_valid()) return 0.0;
    return pc->playback_get_position();
}

// Build a plain-text NSString from LyricData lines (UTF-8 std::string on macOS).
static NSString *plain_text_from_lyrics(const LyricData& lyrics) {
    if (lyrics.IsEmpty()) return nil;
    std::string buf;
    buf.reserve(lyrics.lines.size() * 64);
    for (const LyricDataLine& line : lyrics.lines) {
        if (!buf.empty()) buf += '\n';
        buf += line.text;
    }
    if (buf.empty()) return nil;
    return [[[NSString alloc] initWithBytes:buf.data()
                                     length:buf.size()
                                   encoding:NSUTF8StringEncoding] autorelease];
}

// ---------------------------------------------------------------------------
// OpenLyricsView
// ---------------------------------------------------------------------------

@interface OpenLyricsView () {
    // Lyrics state
    LyricData _lyrics;           // full lyrics (with or without timestamps)
    NSString *_lyricsText;       // plain-text cache (for currentLyricsText / hasLyrics)

    // Rendering
    NSFont   *_font;
    CGFloat   _lineHeight;       // ascent + descent + leading + gap

    // Synced scrolling
    NSTimer  *_scrollTimer;
    CGFloat   _scrollOffset;     // current scroll offset in points (pixels from top of content)
    CGFloat   _targetScrollOffset;
    NSInteger _currentLineIndex;

    // Manual scroll state
    CGFloat   _manualScrollDelta;     // user offset from the auto-scroll position (Windows: m_manual_scroll_distance)
    BOOL      _isDragging;
    CGFloat   _dragStartY;
    CGFloat   _dragStartOffset;       // _scrollOffset at drag start (for immediate feedback)
    CGFloat   _dragStartManualDelta;  // _manualScrollDelta at drag start

    // CTLine cache — rebuilt when lyrics or usable width changes
    NSArray      *_cachedLines;           // flat array of visual rows (CTLineRef via NSValue)
    NSArray      *_lyricLineIndices;      // NSNumber: maps visual row index → _lyrics.lines index
    NSArray      *_firstRowForLyricLine;  // NSNumber: first visual row index for each lyric line
    CGFloat       _cachedLineHeight;  // line height at cache build time
    CGFloat       _cachedLineWidth;   // usable pixel width at cache build time

    // Background image (computed on resize / prefs change / album art change)
    Image            _albumartOriginal;
    Image            _customImgOriginal;
    Image            _backgroundImg;
    CGImageRef       _backgroundCGImage;
    now_playing_album_art_notify *_artNotifyHandle;

    // Now-playing track (set on new track, cleared on stop)
    metadb_handle_ptr _nowPlayingTrack;
    metadb_v2_rec_t   _nowPlayingInfo;

    // Search avoidance state (cleared on new track / clearLyrics)
    SearchAvoidanceReason _autoSearchAvoidedReason;
    uint64_t              _autoSearchAvoidedTimestamp;
}
@end

@implementation OpenLyricsView

// ---------------------------------------------------------------------------
// Class init: create shared CF array + serial queue
// ---------------------------------------------------------------------------

+ (void)initialize {
    if (self == [OpenLyricsView class]) {
        CFArrayCallBacks weakCallbacks = kCFTypeArrayCallBacks;
        weakCallbacks.retain  = NULL;
        weakCallbacks.release = NULL;
        g_active_panels_cf = CFArrayCreateMutable(NULL, 0, &weakCallbacks);
        g_panels_queue = dispatch_queue_create("com.foo_openlyrics.panels", DISPATCH_QUEUE_SERIAL);
    }
}

// ---------------------------------------------------------------------------
// Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        _lyricsText = nil;
        _scrollOffset = 0.0;
        _targetScrollOffset = 0.0;
        _manualScrollDelta = 0.0;
        _currentLineIndex = -1;

        _font = [[NSFont systemFontOfSize:kFontSize] retain];
        [self _recomputeLineHeight];

        _cachedLines = nil;
        _lyricLineIndices = nil;
        _firstRowForLyricLine = nil;
        _cachedLineHeight = _lineHeight;
        _cachedLineWidth  = 0.0;

        _backgroundCGImage = nullptr;
        _artNotifyHandle = nullptr;
        _nowPlayingTrack = nullptr;
        _autoSearchAvoidedReason = SearchAvoidanceReason::Allowed;
        _autoSearchAvoidedTimestamp = 0;

        dispatch_sync(g_panels_queue, ^{
            CFArrayAppendValue(g_active_panels_cf, (__bridge void *)self);
        });

        if (core_api::are_services_available()) {
            // Register for album art changes (service may be absent on macOS).
            now_playing_album_art_notify_manager::ptr art_manager =
                now_playing_album_art_notify_manager::tryGet();
            if (art_manager.is_valid()) {
                OpenLyricsView * __weak weakSelf = self;
                _artNotifyHandle = art_manager->add([weakSelf](album_art_data::ptr art_data) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf onAlbumArtRetrieved:art_data.get_ptr()];
                    });
                });
                // Fetch current album art (if already playing).
                album_art_data::ptr current = art_manager->current();
                if (current.is_valid()) {
                    [self onAlbumArtRetrieved:current.get_ptr()];
                }
            }
            // Load custom background image if configured.
            [self loadCustomBackgroundImage];
        }
    }
    return self;
}

- (void)dealloc {
    [_scrollTimer invalidate];
    [_scrollTimer release];
    _scrollTimer = nil;

    if (_artNotifyHandle != nullptr && core_api::are_services_available()) {
        now_playing_album_art_notify_manager::ptr art_manager =
            now_playing_album_art_notify_manager::tryGet();
        if (art_manager.is_valid()) {
            art_manager->remove(_artNotifyHandle);
        }
        _artNotifyHandle = nullptr;
    }

    if (_backgroundCGImage) { CGImageRelease(_backgroundCGImage); _backgroundCGImage = nullptr; }

    // Safe: g_active_panels_cf holds weak refs (null callbacks), so it cannot
    // be the last retainer of self. dealloc is only called when the last strong
    // ref drops (from the foobar2000 ui_element or the superview hierarchy), which
    // always happens on the main thread, not from g_panels_queue. No deadlock risk.
    dispatch_sync(g_panels_queue, ^{
        CFIndex idx = CFArrayGetFirstIndexOfValue(
            g_active_panels_cf,
            CFRangeMake(0, CFArrayGetCount(g_active_panels_cf)),
            (__bridge void *)self);
        if (idx != kCFNotFound) {
            CFArrayRemoveValueAtIndex(g_active_panels_cf, idx);
        }
    });

    [self _invalidateLineCache];

    [_lyricsText release];
    [_font release];
    [super dealloc];
}

// ---------------------------------------------------------------------------
// View properties
// ---------------------------------------------------------------------------

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped             { return YES; } // Y=0 at top

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self computeBackgroundImage];
    [self setNeedsDisplay:YES];
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [self computeBackgroundImage];
    [self setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// Background rendering
// ---------------------------------------------------------------------------

- (void)loadCustomBackgroundImage {
    const std::string path = preferences::background::custom_image_path();
    if (path.empty()) { _customImgOriginal = {}; return; }
    std::optional<Image> maybe_img = load_image(path.c_str());
    if (maybe_img.has_value()) {
        _customImgOriginal = std::move(maybe_img.value());
    } else {
        _customImgOriginal = {};
    }
}

- (void)onAlbumArtRetrieved:(album_art_data *)art_data {
    // Must be called on main thread.
    if (!art_data) return;

    // Always decode and cache — the preference might change after this fires.
    std::optional<Image> maybe_img = decode_image(art_data->data(), art_data->size());
    if (!maybe_img.has_value()) return;
    _albumartOriginal = std::move(maybe_img.value());

    if (preferences::background::image_type() == BackgroundImageType::AlbumArt) {
        [self computeBackgroundImage];
        [self setNeedsDisplay:YES];
    }
}

// Fetch the current album art from the notification manager if _albumartOriginal is empty.
// Called when the user switches to AlbumArt mode (art may already have been delivered).
- (void)_refreshAlbumArtFromCurrentIfNeeded {
    if (_albumartOriginal.valid()) return;
    if (!core_api::are_services_available()) return;
    now_playing_album_art_notify_manager::ptr art_manager =
        now_playing_album_art_notify_manager::tryGet();
    if (!art_manager.is_valid()) return;
    album_art_data::ptr current = art_manager->current();
    if (!current.is_valid()) return;
    std::optional<Image> maybe_img = decode_image(current->data(), current->size());
    if (maybe_img.has_value()) {
        _albumartOriginal = std::move(maybe_img.value());
    }
}

- (void)computeBackgroundImage {
    const int view_w = (int)self.bounds.size.width;
    const int view_h = (int)self.bounds.size.height;
    if (view_w <= 0 || view_h <= 0) return;

    // 1. Generate the colour/gradient background layer.
    Image bg_colour = {};
    switch (preferences::background::fill_type()) {
        case BackgroundFillType::Default: {
            // Use the same dark constant as the drawRect fallback.
            const RGBAColour rgba = {
                (uint8_t)std::round(kColorBackground[0] * 255),
                (uint8_t)std::round(kColorBackground[1] * 255),
                (uint8_t)std::round(kColorBackground[2] * 255),
                255
            };
            bg_colour = generate_background_colour(view_w, view_h, rgba);
        } break;
        case BackgroundFillType::SolidColour: {
            const t_ui_color c = preferences::background::colour();
            const RGBAColour rgba = { GetRValue(c), GetGValue(c), GetBValue(c), 255 };
            bg_colour = generate_background_colour(view_w, view_h, rgba);
        } break;
        case BackgroundFillType::Gradient: {
            t_ui_color ctl = preferences::background::gradient_tl();
            t_ui_color ctr = preferences::background::gradient_tr();
            t_ui_color cbl = preferences::background::gradient_bl();
            t_ui_color cbr = preferences::background::gradient_br();
            RGBAColour tl = { GetRValue(ctl), GetGValue(ctl), GetBValue(ctl), 255 };
            RGBAColour tr = { GetRValue(ctr), GetGValue(ctr), GetBValue(ctr), 255 };
            RGBAColour bl = { GetRValue(cbl), GetGValue(cbl), GetBValue(cbl), 255 };
            RGBAColour br = { GetRValue(cbr), GetGValue(cbr), GetBValue(cbr), 255 };
            bg_colour = generate_background_colour(view_w, view_h, tl, tr, bl, br);
        } break;
    }

    // 2. Overlay image (album art or custom).
    const BackgroundImageType img_type = preferences::background::image_type();
    if (img_type == BackgroundImageType::None || !bg_colour.valid()) {
        _backgroundImg = std::move(bg_colour);
    } else {
        // Compute placement rect (aspect-ratio-aware, centred).
        const Image& orig = (img_type == BackgroundImageType::AlbumArt)
                            ? _albumartOriginal : _customImgOriginal;

        int img_w = view_w, img_h = view_h;
        int img_x = 0,      img_y = 0;
        if (orig.valid() && preferences::background::maintain_img_aspect_ratio()) {
            const double aspect = double(orig.width) / double(orig.height);
            const int fit_by_y_w = int(view_h * aspect);
            const int fit_by_x_h = int(view_w / aspect);
            if (fit_by_y_w > view_w) {
                img_w = view_w; img_h = fit_by_x_h;
            } else {
                img_w = fit_by_y_w; img_h = view_h;
            }
            img_x = (view_w - img_w) / 2;
            img_y = (view_h - img_h) / 2;
        }

        Image resized = {};
        if (orig.valid()) {
            resized = resize_image(orig, img_w, img_h);
        }

        if (resized.valid()) {
            const double opacity   = preferences::background::image_opacity();
            const int blur_radius  = preferences::background::blur_radius();
            CPoint offset          = { img_x, img_y };
            Image combined = lerp_offset_image(bg_colour, resized, offset, opacity);
            _backgroundImg = blur_image(combined, blur_radius);
        } else {
            _backgroundImg = std::move(bg_colour);
        }
    }

    // 3. Convert to CGImage for drawing.
    if (_backgroundCGImage) { CGImageRelease(_backgroundCGImage); _backgroundCGImage = nullptr; }

    if (_backgroundImg.valid()) {
        const size_t w = (size_t)_backgroundImg.width;
        const size_t h = (size_t)_backgroundImg.height;
        const size_t bytes = w * h * 4;
        CFDataRef data = CFDataCreate(kCFAllocatorDefault, _backgroundImg.pixels, (CFIndex)bytes);
        if (data) {
            CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
            CFRelease(data);
            if (provider) {
                CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                _backgroundCGImage = CGImageCreate(w, h, 8, 32, w * 4, cs,
                                                   kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big,
                                                   provider, nullptr, false,
                                                   kCGRenderingIntentDefault);
                CGColorSpaceRelease(cs);
                CGDataProviderRelease(provider);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Context menu
// ---------------------------------------------------------------------------

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

    // Edit Lyrics
    NSMenuItem *editItem = [menu addItemWithTitle:@"Edit Lyrics"
                                          action:@selector(editLyrics:)
                                   keyEquivalent:@""];
    [editItem setTarget:self];

    // Manual Search
    NSMenuItem *searchItem = [menu addItemWithTitle:@"Manual Search"
                                            action:@selector(manualSearch:)
                                     keyEquivalent:@""];
    [searchItem setTarget:self];

    [menu addItem:[NSMenuItem separatorItem]];

    // Copy Lyrics
    NSMenuItem *copyItem = [menu addItemWithTitle:@"Copy Lyrics"
                                          action:@selector(copyLyrics:)
                                   keyEquivalent:@""];
    [copyItem setTarget:self];
    [copyItem setEnabled:[self hasLyrics]];

    // Reload Lyrics
    BOOL isPlaying = NO;
    if (core_api::are_services_available()) {
        auto pc = play_control::get();
        if (pc.is_valid()) {
            isPlaying = pc->is_playing() ? YES : NO;
        }
    }
    NSMenuItem *reloadItem = [menu addItemWithTitle:@"Reload Lyrics"
                                            action:@selector(reloadLyrics:)
                                     keyEquivalent:@""];
    [reloadItem setTarget:self];
    [reloadItem setEnabled:isPlaying];

    [menu addItem:[NSMenuItem separatorItem]];

    // External Window
    NSMenuItem *extItem = [menu addItemWithTitle:@"External Window"
                                         action:@selector(openExternalWindow:)
                                  keyEquivalent:@""];
    [extItem setTarget:self];

    // Open Preferences
    NSMenuItem *prefsItem = [menu addItemWithTitle:@"Open Preferences"
                                           action:@selector(openPreferences:)
                                    keyEquivalent:@""];
    [prefsItem setTarget:self];

    return menu;
}

- (void)editLyrics:(id)sender {
    SpawnLyricEditorMac();
}

- (void)manualSearch:(id)sender {
    SpawnManualSearchMac();
}

- (void)copyLyrics:(id)sender {
    if (![self hasLyrics]) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:_lyricsText forType:NSPasteboardTypeString];
}

- (void)reloadLyrics:(id)sender {
    if (!core_api::are_services_available()) return;

    auto pc = play_control::get();
    if (!pc.is_valid()) return;

    metadb_handle_ptr track;
    if (!pc->get_now_playing(track)) return;

    const metadb_v2_rec_t track_info = get_full_metadata(track);
    initiate_lyrics_autosearch(track, track_info, true);
}

- (void)openExternalWindow:(id)sender {
    SpawnExternalLyricWindow();
}

- (void)openPreferences:(id)sender {
    if(!core_api::are_services_available()) return;
    ui_control::get()->show_preferences(GUID_PREFERENCES_PAGE_ROOT);
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Scroll event handling (wheel + drag)
// ---------------------------------------------------------------------------

- (void)scrollWheel:(NSEvent *)event {
    if (_lyrics.IsEmpty() || !_lyrics.IsTimestamped()) return;
    CGFloat delta = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) delta *= _lineHeight;
    CGFloat maxScroll = MAX(0.0, (CGFloat)[self _visualRowCount] * _lineHeight - self.bounds.size.height);
    // Accumulate into the manual offset (mirrors Windows m_manual_scroll_distance).
    // Also update _scrollOffset immediately for instant visual feedback.
    _manualScrollDelta -= delta;
    _scrollOffset = MAX(0.0, MIN(maxScroll, _scrollOffset - delta));
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    if (_lyrics.IsEmpty() || !_lyrics.IsTimestamped()) { [super mouseDown:event]; return; }
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    _isDragging = YES;
    _dragStartY = loc.y;
    _dragStartOffset = _scrollOffset;
    _dragStartManualDelta = _manualScrollDelta;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat delta = _dragStartY - loc.y; // positive delta = dragged up = scroll down
    CGFloat maxScroll = MAX(0.0, (CGFloat)[self _visualRowCount] * _lineHeight - self.bounds.size.height);
    _manualScrollDelta = _dragStartManualDelta + delta;
    _scrollOffset = MAX(0.0, MIN(maxScroll, _dragStartOffset + delta));
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
    [super mouseUp:event];
}

// Public API
// ---------------------------------------------------------------------------

- (BOOL)hasLyrics {
    return _lyricsText != nil && _lyricsText.length > 0;
}

- (NSString *)currentLyricsText {
    return _lyricsText;
}

- (BOOL)isTimerRunning {
    return _scrollTimer != nil;
}

- (void)updateLyrics:(const LyricData&)lyrics {
    // Must be called on the main thread.
    _lyrics = lyrics;

    NSString *text = plain_text_from_lyrics(lyrics);
    [_lyricsText release];
    _lyricsText = [text retain];

    _scrollOffset       = 0.0;
    _targetScrollOffset = 0.0;
    _manualScrollDelta  = 0.0;
    _currentLineIndex   = -1;

    [self _stopTimer];
    [self _invalidateLineCache]; // rebuilt lazily in drawRect: with correct width

    if (lyrics.IsTimestamped()) {
        [self _startTimer];
    }

    [self setNeedsDisplay:YES];
}

- (void)clearLyrics {
    // Must be called on the main thread.
    _lyrics = LyricData();

    [_lyricsText release];
    _lyricsText = nil;

    _scrollOffset       = 0.0;
    _targetScrollOffset = 0.0;
    _manualScrollDelta  = 0.0;
    _currentLineIndex   = -1;

    _nowPlayingTrack = nullptr;
    _nowPlayingInfo  = {};
    _autoSearchAvoidedReason = SearchAvoidanceReason::Allowed;

    [self _stopTimer];
    [self _invalidateLineCache];
    [self setNeedsDisplay:YES];
}

- (void)setNowPlayingTrack:(metadb_handle_ptr)track info:(const metadb_v2_rec_t&)info {
    // Must be called on the main thread.
    _nowPlayingTrack = track;
    _nowPlayingInfo  = info;
    _autoSearchAvoidedReason = SearchAvoidanceReason::Allowed;
    [self setNeedsDisplay:YES];
}

- (void)setSearchAvoidedReason:(SearchAvoidanceReason)reason timestamp:(uint64_t)ts {
    // Must be called on the main thread.
    _autoSearchAvoidedReason    = reason;
    _autoSearchAvoidedTimestamp = ts;
    [self setNeedsDisplay:YES];
}

- (LyricData)currentLyricData {
    return _lyrics;
}

- (metadb_handle_ptr)nowPlayingTrack { return _nowPlayingTrack; }
- (metadb_v2_rec_t)nowPlayingInfo    { return _nowPlayingInfo; }

/// Legacy setter kept so existing tests continue to compile and pass.
- (void)setLyricsText:(NSString *)text {
    NSString *newText = (text.length > 0) ? [text retain] : nil;
    [_lyricsText release];
    _lyricsText = newText;

    // Reset LyricData so drawRect renders via the plain-text path.
    _lyrics = LyricData();
    [self _stopTimer];
    [self setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// Timer management
// ---------------------------------------------------------------------------

- (void)_recomputeLineHeight {
    CGFloat lineGap = 8.0;
    if (core_api::are_services_available()) {
        lineGap = (CGFloat)preferences::display::linegap();
    }
    CGFloat ascent  = [_font ascender];
    CGFloat descent = -[_font descender];
    CGFloat leading = [_font leading];
    _lineHeight = ascent + descent + leading + lineGap;
}

- (void)_startTimer {
    if (_scrollTimer) return;
    _scrollTimer = [[NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                     target:self
                                                   selector:@selector(_timerFired:)
                                                   userInfo:nil
                                                    repeats:YES] retain];
}

- (void)_stopTimer {
    if (!_scrollTimer) return;
    [_scrollTimer invalidate];
    [_scrollTimer release];
    _scrollTimer = nil;
}

// ---------------------------------------------------------------------------
// CTLine cache management
// ---------------------------------------------------------------------------

- (void)_invalidateLineCache {
    for (NSValue *v in _cachedLines) {
        CTLineRef line = (CTLineRef)[v pointerValue];
        if (line) CFRelease(line);
    }
    [_cachedLines release];
    _cachedLines = nil;
    [_lyricLineIndices release];
    _lyricLineIndices = nil;
    [_firstRowForLyricLine release];
    _firstRowForLyricLine = nil;
    _cachedLineWidth = 0.0;
}

- (NSInteger)_visualRowCount {
    return (_cachedLines != nil) ? (NSInteger)[_cachedLines count] : (NSInteger)_lyrics.lines.size();
}

// Build the CTLine cache, wrapping long lines to fit within usableWidth.
// Each lyric line may produce multiple visual rows; _lyricLineIndices maps
// each visual row back to its original lyric line index (for synced color).
- (void)_buildLineCache:(CGFloat)usableWidth {
    [self _invalidateLineCache];
    if (_lyrics.IsEmpty()) return;

    NSUInteger lyricCount = _lyrics.lines.size();
    NSMutableArray *rows      = [[NSMutableArray alloc] initWithCapacity:lyricCount];
    NSMutableArray *indices   = [[NSMutableArray alloc] initWithCapacity:lyricCount];
    NSMutableArray *firstRows = [[NSMutableArray alloc] initWithCapacity:lyricCount];

    NSDictionary *attrs = @{
        NSFontAttributeName: _font,
        // Use the CGContext fill color (set per-line in drawRect) instead of a baked-in color.
        (NSString *)kCTForegroundColorFromContextAttributeName: (id)kCFBooleanTrue
    };

    for (NSUInteger lyricIdx = 0; lyricIdx < lyricCount; lyricIdx++) {
        const std::string& lineText = _lyrics.lines[lyricIdx].text;
        NSString *nsLine = [NSString stringWithUTF8String:lineText.c_str()];
        if (!nsLine) nsLine = @"";

        NSAttributedString *attrStr = [[NSAttributedString alloc]
                                       initWithString:nsLine attributes:attrs];
        CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr);
        [attrStr release];

        CFIndex strLen = (CFIndex)[nsLine length]; // UTF-16 length

        [firstRows addObject:@([rows count])]; // first visual row for this lyric line
        if (strLen == 0) {
            // Empty line: one blank visual row to preserve vertical spacing.
            CTLineRef ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0));
            [rows    addObject:[NSValue valueWithPointer:(const void *)ctLine]];
            [indices addObject:@(lyricIdx)];
        } else {
            CFIndex pos = 0;
            while (pos < strLen) {
                CFIndex breakLen = (usableWidth > 0.0)
                    ? CTTypesetterSuggestLineBreak(typesetter, pos, (double)usableWidth)
                    : (strLen - pos);
                if (breakLen <= 0) breakLen = strLen - pos; // safeguard: never infinite-loop
                CTLineRef ctLine = CTTypesetterCreateLine(typesetter,
                                                         CFRangeMake(pos, breakLen));
                [rows    addObject:[NSValue valueWithPointer:(const void *)ctLine]];
                [indices addObject:@(lyricIdx)];
                pos += breakLen;
            }
        }
        CFRelease(typesetter);
    }

    _cachedLines          = [rows copy];
    _lyricLineIndices     = [indices copy];
    _firstRowForLyricLine = [firstRows copy];
    _cachedLineWidth  = usableWidth;
    _cachedLineHeight = _lineHeight;
    [rows      release];
    [indices   release];
    [firstRows release];
}

- (void)_timerFired:(NSTimer *)timer {
    [self _updateScrollPosition];
    [self setNeedsDisplay:YES];
}

// Determines which line is current and updates the target scroll offset.
- (void)_updateScrollPosition {
    if (_lyrics.IsEmpty() || !_lyrics.IsTimestamped()) return;
    // In manual-scroll mode, don't auto-scroll — only update the current line index.
    BOOL autoScroll = YES;
    if (core_api::are_services_available()) {
        autoScroll = (preferences::display::scroll_type() == LineScrollType::Automatic);
    }

    double now = get_playback_time();
    NSInteger lineCount = (NSInteger)_lyrics.lines.size();

    // Assumes LyricData::lines are sorted by timestamp ascending (guaranteed by LRC parser).
    // Find last line whose timestamp <= now
    NSInteger newLine = -1;
    for (NSInteger i = 0; i < lineCount; i++) {
        double ts = _lyrics.LineTimestamp((int)i);
        if (ts <= now) {
            newLine = i;
        } else {
            break;
        }
    }
    _currentLineIndex = newLine;

    if (autoScroll) {
        // Target: center the current line vertically.
        // With word wrap, find the first visual row for _currentLineIndex.
        if (newLine >= 0) {
            NSInteger visualRow = newLine; // 1:1 fallback if cache unavailable
            if (_firstRowForLyricLine && newLine < (NSInteger)[_firstRowForLyricLine count]) {
                visualRow = [[_firstRowForLyricLine objectAtIndex:(NSUInteger)newLine] integerValue];
            }
            CGFloat lineCenter = visualRow * _lineHeight + _lineHeight / 2.0;
            _targetScrollOffset = lineCenter - self.bounds.size.height / 2.0;
        } else {
            _targetScrollOffset = 0.0;
        }

        // Combine auto-scroll target with the user's manual offset, then clamp.
        NSInteger visualRowCount = [self _visualRowCount];
        CGFloat totalHeight = visualRowCount * _lineHeight;
        CGFloat maxScroll = totalHeight - self.bounds.size.height;
        if (maxScroll < 0.0) maxScroll = 0.0;
        CGFloat combinedTarget = _targetScrollOffset + _manualScrollDelta;
        if (combinedTarget < 0.0) combinedTarget = 0.0;
        if (combinedTarget > maxScroll) combinedTarget = maxScroll;

        // Lerp toward target. Use scroll_time_seconds pref to derive factor.
        CGFloat lerpFactor = kScrollLerp;
        if (core_api::are_services_available()) {
            double scrollSecs = preferences::display::scroll_time_seconds();
            if (scrollSecs <= 0.0 || scrollSecs > 60.0) {
                lerpFactor = 1.0; // instant
            } else {
                // k such that 95% completion in scrollSecs at 60 Hz
                lerpFactor = (CGFloat)(1.0 - std::exp(std::log(0.05) / (scrollSecs * 60.0)));
            }
        }
        _scrollOffset += (combinedTarget - _scrollOffset) * lerpFactor;
    }
}

// ---------------------------------------------------------------------------
// drawRect: Core Text rendering pipeline
// ---------------------------------------------------------------------------

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // 1. Fill background
    if (_backgroundCGImage) {
        CGContextDrawImage(ctx, NSRectToCGRect(self.bounds), _backgroundCGImage);
    } else {
        CGContextSetRGBFillColor(ctx, kColorBackground[0], kColorBackground[1],
                                 kColorBackground[2], kColorBackground[3]);
        CGContextFillRect(ctx, NSRectToCGRect(self.bounds));
    }

    BOOL hasContent = (_lyricsText != nil && _lyricsText.length > 0);
    BOOL isSynced   = !_lyrics.IsEmpty() && _lyrics.IsTimestamped();
    BOOL isUnsynced = !_lyrics.IsEmpty() && !_lyrics.IsTimestamped();

    // 2. No lyrics state
    if (!hasContent) {
        [self _drawNoLyricsInContext:ctx];
        return;
    }

    // 3. Core Text rendering
    // isFlipped=YES means AppKit draws Y=0 at top, but CGContext/Core Text
    // wants Y=0 at bottom.  We flip the context so Core Text sees standard
    // (bottom-origin) coordinates while we address lines from top.
    CGFloat viewHeight = self.bounds.size.height;
    CGFloat viewWidth  = self.bounds.size.width;
    const CGFloat usableWidth = viewWidth - 2.0 * kSidePadding;

    // Rebuild CTLine cache if stale (new lyrics, resize, font change).
    if (_cachedLines == nil || _cachedLineWidth != usableWidth || _cachedLineHeight != _lineHeight) {
        [self _buildLineCache:usableWidth];
    }
    NSInteger visualRowCount = [self _visualRowCount];

    CGContextSaveGState(ctx);
    // Flip: translate to bottom-left, scale Y by -1 (now top = viewHeight, bottom = 0)
    CGContextTranslateCTM(ctx, 0.0, viewHeight);
    CGContextScaleCTM(ctx, 1.0, -1.0);

    // Read display preferences once per draw (only when services are available).
    CGFloat colorNormal[4], colorHighlight[4], colorPast[4];
    TextAlignment alignment = TextAlignment::MidCentre;
    if (core_api::are_services_available()) {
        alignment = preferences::display::text_alignment();
        colorref_to_cgfloat(preferences::display::main_text_colour(),  colorNormal);
        colorref_to_cgfloat(preferences::display::highlight_colour(),   colorHighlight);
        colorref_to_cgfloat(preferences::display::past_text_colour(),   colorPast);
    } else {
        memcpy(colorNormal,    kColorNormal,    sizeof(colorNormal));
        memcpy(colorHighlight, kColorHighlight, sizeof(colorHighlight));
        memcpy(colorPast,      kColorPast,      sizeof(colorPast));
    }

    // Vertical start position.
    // For unsynced lyrics: center vertically for Mid* alignment, top-align for Top*.
    // For synced lyrics: driven by scrollOffset.
    bool isTopAligned = (alignment == TextAlignment::TopCentre ||
                         alignment == TextAlignment::TopLeft   ||
                         alignment == TextAlignment::TopRight);

    CGFloat startY; // Y in top-origin space (distance from top of view)
    if (isUnsynced) {
        CGFloat totalHeight = visualRowCount * _lineHeight;
        if (!isTopAligned && totalHeight < viewHeight) {
            startY = (viewHeight - totalHeight) / 2.0;
        } else {
            startY = kTopPadding;
        }
    } else if (isSynced) {
        startY = -_scrollOffset; // scrollOffset pushes content up
    } else {
        // plain-text fallback (legacy setLyricsText: path)
        startY = kTopPadding;
    }

    CGFloat ascent = [_font ascender];

    for (NSInteger i = 0; i < visualRowCount; i++) {
        // Top edge of this visual row in top-origin space
        CGFloat lineTop = startY + i * _lineHeight;
        // Skip rows fully outside the view
        if (lineTop + _lineHeight < 0) continue;
        if (lineTop > viewHeight) break;

        // Map visual row → lyric line index for synced color selection.
        NSInteger lyricIdx = (_lyricLineIndices && i < (NSInteger)[_lyricLineIndices count])
            ? [[_lyricLineIndices objectAtIndex:(NSUInteger)i] integerValue]
            : i;

        // Determine color
        const CGFloat *color;
        if (isSynced) {
            if (lyricIdx == _currentLineIndex) {
                color = colorHighlight;
            } else if (lyricIdx < _currentLineIndex) {
                color = colorPast;
            } else {
                color = colorNormal;
            }
        } else {
            color = colorNormal;
        }

        CGContextSetRGBFillColor(ctx, color[0], color[1], color[2], color[3]);

        // Retrieve cached CTLine (no allocation per frame).
        CTLineRef ctLine = (CTLineRef)[[_cachedLines objectAtIndex:(NSUInteger)i] pointerValue];
        if (!ctLine) continue;

        CGFloat lineBaselineCT = viewHeight - lineTop - ascent;

        // Horizontal position based on alignment preference.
        CGFloat lineWidth = (CGFloat)CTLineGetTypographicBounds(ctLine, NULL, NULL, NULL);
        CGFloat xPos;
        switch (alignment) {
            case TextAlignment::TopLeft:
            case TextAlignment::MidLeft:
                xPos = kSidePadding;
                break;
            case TextAlignment::TopRight:
            case TextAlignment::MidRight:
                xPos = viewWidth - lineWidth - kSidePadding;
                break;
            default: // TopCentre / MidCentre
                xPos = kSidePadding + (usableWidth - lineWidth) / 2.0;
                break;
        }
        if (xPos < kSidePadding) xPos = kSidePadding;

        CGContextSetTextPosition(ctx, xPos, lineBaselineCT);
        CTLineDraw(ctLine, ctx);
    }

    CGContextRestoreGState(ctx);
}

// ---------------------------------------------------------------------------
// No-lyrics placeholder
// ---------------------------------------------------------------------------

- (void)_drawNoLyricsInContext:(CGContextRef __unused)ctx {
    if (_nowPlayingTrack == nullptr) return;

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: [NSColor colorWithRed:kColorDim[0]
                                                        green:kColorDim[1]
                                                         blue:kColorDim[2]
                                                        alpha:kColorDim[3]]
    };

    // Build lines: Artist / Album / Title, then progress or avoidance message.
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    {
        std::string artist = track_metadata(_nowPlayingInfo, "artist");
        std::string album  = track_metadata(_nowPlayingInfo, "album");
        std::string title  = track_metadata(_nowPlayingInfo, "title");
        if (!artist.empty())
            [lines addObject:[NSString stringWithFormat:@"Artist: %s", artist.c_str()]];
        if (!album.empty())
            [lines addObject:[NSString stringWithFormat:@"Album: %s",  album.c_str()]];
        if (!title.empty())
            [lines addObject:[NSString stringWithFormat:@"Title: %s",  title.c_str()]];
    }

    std::optional<std::string> progress = get_autosearch_progress_message();
    if (progress.has_value()) {
        [lines addObject:[NSString stringWithUTF8String:progress->c_str()]];
    } else if (_autoSearchAvoidedReason != SearchAvoidanceReason::Allowed) {
        const double kMsgSeconds = 15.0;
        uint64_t elapsed = filetimestamp_from_system_timer() - _autoSearchAvoidedTimestamp;
        if (elapsed < static_cast<uint64_t>(kMsgSeconds * 10'000'000)) {
            [lines addObject:@""];
            switch (_autoSearchAvoidedReason) {
                case SearchAvoidanceReason::RepeatedFailures:
                    [lines addObject:@"Auto-search skipped: search failed too many times."];
                    [lines addObject:@"Manually request a lyrics search to try again."];
                    break;
                case SearchAvoidanceReason::MarkedInstrumental:
                    [lines addObject:@"Auto-search skipped: track was explicitly marked 'instrumental'"];
                    [lines addObject:@"Manually request a lyrics search to clear that status."];
                    break;
                case SearchAvoidanceReason::MatchesSkipFilter:
                    [lines addObject:@"Auto-search skipped: track matched the skip filter."];
                    break;
                default: break;
            }
        }
    }

    if (lines.count == 0) return;

    CGFloat lineH = [@"A" sizeWithAttributes:attrs].height + 4.0;
    CGFloat totalH = lineH * lines.count;
    CGFloat y = NSMidY(self.bounds) + totalH / 2.0 - lineH;

    for (NSString *line in lines) {
        NSSize sz = [line sizeWithAttributes:attrs];
        NSPoint pt = NSMakePoint(NSMidX(self.bounds) - sz.width / 2.0, y);
        [line drawAtPoint:pt withAttributes:attrs];
        y -= lineH;
    }
}

@end

// ---------------------------------------------------------------------------
// Panel hook implementations
// ---------------------------------------------------------------------------

size_t num_visible_lyric_panels() {
    __block size_t count = 0;
    dispatch_sync(g_panels_queue, ^{
        CFIndex total = CFArrayGetCount(g_active_panels_cf);
        for (CFIndex i = 0; i < total; i++) {
            OpenLyricsView *v = (__bridge OpenLyricsView *)
                CFArrayGetValueAtIndex(g_active_panels_cf, i);
            if (v.window != nil) count++;
        }
    });
    return count;
}

void recompute_lyric_panel_backgrounds() {
    __block NSArray *snapshot = nil;
    dispatch_sync(g_panels_queue, ^{
        CFIndex count = CFArrayGetCount(g_active_panels_cf);
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (CFIndex i = 0; i < count; i++) {
            OpenLyricsView *v = (OpenLyricsView *)
                CFArrayGetValueAtIndex(g_active_panels_cf, i);
            [arr addObject:v];
        }
        snapshot = [arr retain];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        for (OpenLyricsView *v in snapshot) {
            [v _recomputeLineHeight];
            [v _invalidateLineCache];
            [v loadCustomBackgroundImage];
            [v _refreshAlbumArtFromCurrentIfNeeded];
            [v computeBackgroundImage];
            [v setNeedsDisplay:YES];
        }
        [snapshot release];
    });
}

void repaint_all_lyric_panels() {
    __block NSArray *snapshot = nil;
    dispatch_sync(g_panels_queue, ^{
        CFIndex count = CFArrayGetCount(g_active_panels_cf);
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (CFIndex i = 0; i < count; i++) {
            OpenLyricsView *v = (OpenLyricsView *)
                CFArrayGetValueAtIndex(g_active_panels_cf, i);
            [arr addObject:v];
        }
        snapshot = [arr retain];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        for (OpenLyricsView *v in snapshot) {
            [v setNeedsDisplay:YES];
        }
        [snapshot release];
    });
}

void clear_all_lyric_panels() {
    __block NSArray *snapshot = nil;
    dispatch_sync(g_panels_queue, ^{
        CFIndex count = CFArrayGetCount(g_active_panels_cf);
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (CFIndex i = 0; i < count; i++) {
            OpenLyricsView *v = (OpenLyricsView *)
                CFArrayGetValueAtIndex(g_active_panels_cf, i);
            [arr addObject:v];
        }
        snapshot = [arr retain];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        for (OpenLyricsView *v in snapshot) {
            [v clearLyrics];
        }
        [snapshot release];
    });
}

// ---------------------------------------------------------------------------
// announce_lyric_update: called from LyricAutosearchManager's background
// thread when a search result arrives.
// ---------------------------------------------------------------------------

LyricData get_active_panel_lyrics(metadb_handle_ptr& out_track, metadb_v2_rec_t& out_info) {
    // Must be called on main thread.
    __block LyricData result;
    __block metadb_handle_ptr track;
    __block metadb_v2_rec_t info;
    dispatch_sync(g_panels_queue, ^{
        CFIndex count = CFArrayGetCount(g_active_panels_cf);
        for (CFIndex i = 0; i < count; i++) {
            OpenLyricsView *v = (__bridge OpenLyricsView *)
                CFArrayGetValueAtIndex(g_active_panels_cf, i);
            if ([v hasLyrics]) {
                result = [v currentLyricData];
                track  = [v nowPlayingTrack];
                info   = [v nowPlayingInfo];
                break;
            }
        }
    });
    out_track = track;
    out_info  = info;
    return result;
}

void announce_lyric_update(LyricUpdate update) {
    // Heap-allocate the update so it can be safely moved across the async boundary.
    metadb_handle_ptr track    = update.track;
    metadb_v2_rec_t  *infoPtr  = new metadb_v2_rec_t(update.track_info);
    LyricUpdate      *updatePtr = new LyricUpdate(std::move(update));

    dispatch_async(dispatch_get_main_queue(), ^{
        // process_available_lyric_update applies automated auto-edits (e.g. HTML entity
        // decoding) and saves the lyrics — matching the Windows announce_lyric_update flow.
        std::optional<LyricData> maybe_lyrics =
            io::process_available_lyric_update(std::move(*updatePtr));
        delete updatePtr;

        if (!maybe_lyrics.has_value()) {
            delete infoPtr;
            return;
        }

        LyricData *lyricsPtr = new LyricData(std::move(maybe_lyrics.value()));

        __block NSArray *snapshot = nil;
        dispatch_sync(g_panels_queue, ^{
            CFIndex count = CFArrayGetCount(g_active_panels_cf);
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            for (CFIndex i = 0; i < count; i++) {
                OpenLyricsView *v = (OpenLyricsView *)
                    CFArrayGetValueAtIndex(g_active_panels_cf, i);
                [arr addObject:v];
            }
            snapshot = [arr retain];
        });
        for (OpenLyricsView *v in snapshot) {
            [v setNowPlayingTrack:track info:*infoPtr];
            [v updateLyrics:*lyricsPtr];
        }
        [snapshot release];
        delete lyricsPtr;
        delete infoPtr;
    });
}

void set_now_playing_track(metadb_handle_ptr track, metadb_v2_rec_t info) {
    metadb_v2_rec_t *infoPtr = new metadb_v2_rec_t(std::move(info));
    dispatch_async(dispatch_get_main_queue(), ^{
        __block NSArray *snapshot = nil;
        dispatch_sync(g_panels_queue, ^{
            CFIndex count = CFArrayGetCount(g_active_panels_cf);
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            for (CFIndex i = 0; i < count; i++) {
                OpenLyricsView *v = (OpenLyricsView *)
                    CFArrayGetValueAtIndex(g_active_panels_cf, i);
                [arr addObject:v];
            }
            snapshot = [arr retain];
        });
        for (OpenLyricsView *v in snapshot) {
            [v setNowPlayingTrack:track info:*infoPtr];
        }
        [snapshot release];
        delete infoPtr;
    });
}

void announce_lyric_search_avoided(metadb_handle_ptr track, SearchAvoidanceReason avoid_reason) {
    uint64_t ts = filetimestamp_from_system_timer();
    dispatch_async(dispatch_get_main_queue(), ^{
        __block NSArray *snapshot = nil;
        dispatch_sync(g_panels_queue, ^{
            CFIndex count = CFArrayGetCount(g_active_panels_cf);
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            for (CFIndex i = 0; i < count; i++) {
                OpenLyricsView *v = (OpenLyricsView *)
                    CFArrayGetValueAtIndex(g_active_panels_cf, i);
                [arr addObject:v];
            }
            snapshot = [arr retain];
        });
        for (OpenLyricsView *v in snapshot) {
            if ([v nowPlayingTrack] == track) {
                [v setSearchAvoidedReason:avoid_reason timestamp:ts];
            }
        }
        [snapshot release];
    });
}
