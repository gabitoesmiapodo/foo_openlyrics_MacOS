// mac/OpenLyricsView.mm
#import "stdafx.h"
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

#include "../src/img_processing.h"
#include "../src/lyric_search.h"
#include "../src/preferences.h"
#include "../src/tag_util.h"
#include "../src/ui_hooks.h"

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------

// SpawnLyricEditorMac is defined in OpenLyricsEditor.mm.
void SpawnLyricEditorMac();
// SpawnManualSearchMac stub is in MacStubs.mm.
void SpawnManualSearchMac();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

static const CGFloat kFontSize      = 18.0;
static const CGFloat kLineGap       = 8.0;
static const CGFloat kScrollLerp    = 0.12; // fraction toward target per tick (~60 Hz)

// Colors (RGBA)
static const CGFloat kColorNormal[4]    = { 1.0, 1.0, 1.0, 1.0 };
static const CGFloat kColorHighlight[4] = { 1.0, 0.85, 0.0, 1.0 };
static const CGFloat kColorPast[4]      = { 0.5, 0.5, 0.5, 1.0 };
static const CGFloat kColorDim[4]       = { 0.55, 0.55, 0.55, 1.0 };
static const CGFloat kColorBackground[4]= { 0.102, 0.102, 0.102, 1.0 }; // #1A1A1A

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

    // CTLine cache — rebuilt when lyrics change, not per frame
    NSArray      *_cachedLines;      // array of CTLine (bridged as id via NSValue+pointerValue)
    CGColorSpaceRef _colorSpace;     // device RGB, created once in initWithFrame:
    CGFloat       _cachedLineHeight; // pre-computed line height stored alongside cache

    // Background image (computed on resize / prefs change / album art change)
    Image            _albumartOriginal;
    Image            _customImgOriginal;
    Image            _backgroundImg;
    CGImageRef       _backgroundCGImage;
    now_playing_album_art_notify *_artNotifyHandle;
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
        _currentLineIndex = -1;

        _font = [[NSFont systemFontOfSize:kFontSize] retain];

        // Measure line height using font metrics
        CGFloat ascent  = [_font ascender];
        CGFloat descent = -[_font descender]; // descender is negative
        CGFloat leading = [_font leading];
        _lineHeight = ascent + descent + leading + kLineGap;

        _colorSpace = CGColorSpaceCreateDeviceRGB();
        _cachedLines = nil;
        _cachedLineHeight = _lineHeight;

        _backgroundCGImage = nullptr;
        _artNotifyHandle = nullptr;

        dispatch_sync(g_panels_queue, ^{
            CFArrayAppendValue(g_active_panels_cf, (__bridge void *)self);
        });

        if (core_api::are_services_available()) {
            // Register for album art changes.
            now_playing_album_art_notify_manager::ptr art_manager =
                now_playing_album_art_notify_manager::get();
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
            now_playing_album_art_notify_manager::get();
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
    if (_colorSpace) { CGColorSpaceRelease(_colorSpace); _colorSpace = NULL; }

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
    if (preferences::background::image_type() != BackgroundImageType::AlbumArt) return;

    std::optional<Image> maybe_img = decode_image(art_data->data(), art_data->size());
    if (!maybe_img.has_value()) return;
    _albumartOriginal = std::move(maybe_img.value());
    [self computeBackgroundImage];
    [self setNeedsDisplay:YES];
}

- (void)computeBackgroundImage {
    const int view_w = (int)self.bounds.size.width;
    const int view_h = (int)self.bounds.size.height;
    if (view_w <= 0 || view_h <= 0) return;

    // 1. Generate the colour/gradient background layer.
    Image bg_colour = {};
    switch (preferences::background::fill_type()) {
        case BackgroundFillType::Default: {
            const t_ui_color c = preferences::background::colour();
            const RGBAColour rgba = { GetRValue(c), GetGValue(c), GetBValue(c), 255 };
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
    (void)prefsItem;

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
    _currentLineIndex   = -1;

    [self _stopTimer];
    [self _buildLineCache];

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
    _currentLineIndex   = -1;

    [self _stopTimer];
    [self _invalidateLineCache];
    [self setNeedsDisplay:YES];
}

- (LyricData)currentLyricData {
    return _lyrics;
}

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
}

- (void)_buildLineCache {
    [self _invalidateLineCache];
    if (_lyrics.IsEmpty()) return;

    NSUInteger count = _lyrics.lines.size();
    NSMutableArray *arr = [[NSMutableArray alloc] initWithCapacity:count];

    NSMutableParagraphStyle *paraStyle = [[NSMutableParagraphStyle alloc] init];
    paraStyle.alignment = NSTextAlignmentCenter;

    for (NSUInteger i = 0; i < count; i++) {
        const std::string& lineText = _lyrics.lines[i].text;
        NSString *nsLine = [NSString stringWithUTF8String:lineText.c_str()];
        if (!nsLine) nsLine = @"";

        NSDictionary *attrs = @{
            NSFontAttributeName: _font,
            NSParagraphStyleAttributeName: paraStyle
        };
        NSAttributedString *attrStr = [[NSAttributedString alloc]
                                       initWithString:nsLine attributes:attrs];

        CTLineRef ctLine = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr);
        [attrStr release];

        // CFRetain was done implicitly by CTLineCreateWithAttributedString.
        // Wrap raw pointer — NSValue does NOT retain CF objects.
        [arr addObject:[NSValue valueWithPointer:(const void *)ctLine]];
    }

    [paraStyle release];
    _cachedLines = [arr copy];
    [arr release];
    _cachedLineHeight = _lineHeight;
}

- (void)_timerFired:(NSTimer *)timer {
    [self _updateScrollPosition];
    [self setNeedsDisplay:YES];
}

// Determines which line is current and updates the target scroll offset.
- (void)_updateScrollPosition {
    if (_lyrics.IsEmpty() || !_lyrics.IsTimestamped()) return;

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

    // Target: center the current line vertically
    if (newLine >= 0) {
        CGFloat lineCenter = newLine * _lineHeight + _lineHeight / 2.0;
        _targetScrollOffset = lineCenter - self.bounds.size.height / 2.0;
    } else {
        _targetScrollOffset = 0.0;
    }

    // Clamp target to valid range
    CGFloat totalHeight = lineCount * _lineHeight;
    CGFloat maxScroll = totalHeight - self.bounds.size.height;
    if (maxScroll < 0.0) maxScroll = 0.0;
    if (_targetScrollOffset < 0.0) _targetScrollOffset = 0.0;
    if (_targetScrollOffset > maxScroll) _targetScrollOffset = maxScroll;

    // Linear interpolation toward target
    _scrollOffset += (_targetScrollOffset - _scrollOffset) * kScrollLerp;
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

    CGContextSaveGState(ctx);
    // Flip: translate to bottom-left, scale Y by -1 (now top = viewHeight, bottom = 0)
    CGContextTranslateCTM(ctx, 0.0, viewHeight);
    CGContextScaleCTM(ctx, 1.0, -1.0);

    NSInteger lineCount = (NSInteger)_lyrics.lines.size();

    // For unsynced lyrics, center the block vertically if it fits, else top-align
    CGFloat startY; // Y in flipped-back "top-origin" space (distance from top)
    if (isUnsynced) {
        CGFloat totalHeight = lineCount * _lineHeight;
        if (totalHeight < viewHeight) {
            startY = (viewHeight - totalHeight) / 2.0;
        } else {
            startY = 0.0;
        }
    } else if (isSynced) {
        startY = -_scrollOffset; // scrollOffset pushes content up
    } else {
        // plain-text fallback (legacy setLyricsText: path)
        startY = 8.0;
    }

    CGFloat ascent = [_font ascender];

    for (NSInteger i = 0; i < lineCount; i++) {
        // Top edge of this line in top-origin space
        CGFloat lineTop = startY + i * _lineHeight;
        // Skip lines fully outside the view
        if (lineTop + _lineHeight < 0) continue;
        if (lineTop > viewHeight) break;

        // Determine color
        const CGFloat *color;
        if (isSynced) {
            if (i == _currentLineIndex) {
                color = kColorHighlight;
            } else if (i < _currentLineIndex) {
                color = kColorPast;
            } else {
                color = kColorNormal;
            }
        } else {
            color = kColorNormal;
        }

        // Apply color to a temporary copy of the cached CTLine.
        // CTLineCreateWithAttributedString was done once in _buildLineCache;
        // here we only re-apply the per-frame color via a new attributed string
        // built from the cached line's runs, or we draw and set the fill color
        // via CGContextSetFillColorSpace before drawing.
        CGColorRef cgColor = CGColorCreate(_colorSpace, color);
        CGContextSetFillColorWithColor(ctx, cgColor);
        CGColorRelease(cgColor);

        // Retrieve cached CTLine (no allocation per frame).
        CTLineRef ctLine = NULL;
        if (_cachedLines && i < (NSInteger)[_cachedLines count]) {
            ctLine = (CTLineRef)[[_cachedLines objectAtIndex:(NSUInteger)i] pointerValue];
        }
        if (!ctLine) continue;

        // CTLineDraw draws at the current text position (baseline).
        // In flipped Core Text space: Y increases upward.
        // lineTop is distance from the *top* of the view.
        // Convert to Core Text Y (distance from bottom) and place baseline at
        // (viewHeight - lineTop - ascent).
        CGFloat lineBaselineCT = viewHeight - lineTop - ascent;

        // Compute line width for centering
        CGFloat lineWidth = (CGFloat)CTLineGetTypographicBounds(ctLine, NULL, NULL, NULL);
        CGFloat xPos = (viewWidth - lineWidth) / 2.0;
        if (xPos < 0.0) xPos = 0.0;

        CGContextSetTextPosition(ctx, xPos, lineBaselineCT);
        CTLineDraw(ctLine, ctx);
    }

    CGContextRestoreGState(ctx);
}

// ---------------------------------------------------------------------------
// No-lyrics placeholder
// ---------------------------------------------------------------------------

- (void)_drawNoLyricsInContext:(CGContextRef)ctx {
    NSString *placeholder = @"No lyrics loaded";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: [NSColor colorWithRed:kColorDim[0]
                                                        green:kColorDim[1]
                                                         blue:kColorDim[2]
                                                        alpha:kColorDim[3]]
    };
    NSSize textSize = [placeholder sizeWithAttributes:attrs];
    NSPoint origin = NSMakePoint(
        NSMidX(self.bounds) - textSize.width  / 2.0,
        NSMidY(self.bounds) - textSize.height / 2.0
    );
    [placeholder drawAtPoint:origin withAttributes:attrs];
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
            [v loadCustomBackgroundImage];
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
    dispatch_sync(g_panels_queue, ^{
        CFIndex count = CFArrayGetCount(g_active_panels_cf);
        for (CFIndex i = 0; i < count; i++) {
            OpenLyricsView *v = (__bridge OpenLyricsView *)
                CFArrayGetValueAtIndex(g_active_panels_cf, i);
            if ([v hasLyrics]) {
                result = [v currentLyricData];
                break;
            }
        }
    });
    return result;
}

void announce_lyric_update(LyricUpdate update) {
    // Heap-allocate so we can safely move across the async dispatch boundary.
    LyricData *lyricsPtr = new LyricData(std::move(update.lyrics));

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
            [v updateLyrics:*lyricsPtr];
        }
        [snapshot release];
        delete lyricsPtr;
    });
}
