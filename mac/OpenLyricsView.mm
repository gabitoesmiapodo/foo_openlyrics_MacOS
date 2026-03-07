// mac/OpenLyricsView.mm
#import "stdafx.h"
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

#include "../src/ui_hooks.h"

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
// Global lyrics state (main thread only)
// ---------------------------------------------------------------------------

static LyricData g_current_lyrics;

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

        dispatch_sync(g_panels_queue, ^{
            CFArrayAppendValue(g_active_panels_cf, (__bridge void *)self);
        });
    }
    return self;
}

- (void)dealloc {
    [_scrollTimer invalidate];
    [_scrollTimer release];
    _scrollTimer = nil;

    dispatch_sync(g_panels_queue, ^{
        CFIndex idx = CFArrayGetFirstIndexOfValue(
            g_active_panels_cf,
            CFRangeMake(0, CFArrayGetCount(g_active_panels_cf)),
            (__bridge void *)self);
        if (idx != kCFNotFound) {
            CFArrayRemoveValueAtIndex(g_active_panels_cf, idx);
        }
    });

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
    [self setNeedsDisplay:YES];
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
    [self setNeedsDisplay:YES];
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

- (void)_timerFired:(NSTimer *)timer {
    [self _updateScrollPosition];
    [self setNeedsDisplay:YES];
}

// Determines which line is current and updates the target scroll offset.
- (void)_updateScrollPosition {
    if (_lyrics.IsEmpty() || !_lyrics.IsTimestamped()) return;

    double now = get_playback_time();
    NSInteger lineCount = (NSInteger)_lyrics.lines.size();

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
    CGContextSetRGBFillColor(ctx, kColorBackground[0], kColorBackground[1],
                             kColorBackground[2], kColorBackground[3]);
    CGContextFillRect(ctx, NSRectToCGRect(self.bounds));

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

        // Build attributed string
        const std::string& lineText = _lyrics.lines[i].text;
        NSString *nsLine = [NSString stringWithUTF8String:lineText.c_str()];
        if (!nsLine) nsLine = @"";

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGColorRef cgColor = CGColorCreate(colorSpace, color);
        CGColorSpaceRelease(colorSpace);

        NSDictionary *attrs = @{
            NSFontAttributeName: _font,
            NSForegroundColorAttributeName: [NSColor colorWithCGColor:cgColor]
        };
        CGColorRelease(cgColor);

        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]
                                              initWithString:nsLine
                                                  attributes:attrs];

        // Center alignment via paragraph style
        NSMutableParagraphStyle *paraStyle = [[NSMutableParagraphStyle alloc] init];
        paraStyle.alignment = NSTextAlignmentCenter;
        [attrStr addAttribute:NSParagraphStyleAttributeName
                        value:paraStyle
                        range:NSMakeRange(0, attrStr.length)];
        [paraStyle release];

        CTLineRef ctLine = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr);
        [attrStr release];

        // CTLineDraw draws at the current text position (baseline).
        // In flipped Core Text space: Y increases upward.
        // lineTop is distance from the *top* of the view.
        // Convert to Core Text Y (distance from bottom) and place baseline at
        // (viewHeight - lineTop - ascent).
        CGFloat ascent  = [_font ascender];
        CGFloat lineBaselineCT = viewHeight - lineTop - ascent;

        // Compute line width for centering
        CGFloat lineWidth = (CGFloat)CTLineGetTypographicBounds(ctLine, NULL, NULL, NULL);
        CGFloat xPos = (viewWidth - lineWidth) / 2.0;
        if (xPos < 0.0) xPos = 0.0;

        CGContextSetTextPosition(ctx, xPos, lineBaselineCT);
        CTLineDraw(ctLine, ctx);
        CFRelease(ctLine);
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

void announce_lyric_update(LyricUpdate update) {
    // Heap-allocate so we can safely move across the async dispatch boundary.
    LyricData *lyricsPtr = new LyricData(std::move(update.lyrics));

    dispatch_async(dispatch_get_main_queue(), ^{
        g_current_lyrics = *lyricsPtr;

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
