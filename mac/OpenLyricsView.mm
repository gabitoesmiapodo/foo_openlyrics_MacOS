// mac/OpenLyricsView.mm
#import "stdafx.h"
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

#include "../src/lyric_data.h"
#include "../src/lyric_io.h"
#include "../src/ui_hooks.h"

// ---------------------------------------------------------------------------
// Global lyrics state (written from announce_lyric_update, read on main thread)
// ---------------------------------------------------------------------------

static LyricData g_current_lyrics;
static NSString *g_current_lyrics_text = nil; // cached plain-text rendering
static dispatch_queue_t g_lyrics_queue;       // serialises writes to g_current_lyrics

// ---------------------------------------------------------------------------
// Active panel registry (weak references via CF)
// ---------------------------------------------------------------------------

static CFMutableArrayRef g_active_panels_cf;
static dispatch_queue_t g_panels_queue;

// ---------------------------------------------------------------------------
// OpenLyricsView
// ---------------------------------------------------------------------------

@interface OpenLyricsView () {
    NSString *_lyricsText; // nil → "No lyrics loaded"
}
@end

@implementation OpenLyricsView

+ (void)initialize {
    if (self == [OpenLyricsView class]) {
        CFArrayCallBacks weakCallbacks = kCFTypeArrayCallBacks;
        weakCallbacks.retain = NULL;
        weakCallbacks.release = NULL;
        g_active_panels_cf = CFArrayCreateMutable(NULL, 0, &weakCallbacks);
        g_panels_queue = dispatch_queue_create("com.foo_openlyrics.panels", DISPATCH_QUEUE_SERIAL);
        g_lyrics_queue = dispatch_queue_create("com.foo_openlyrics.lyrics", DISPATCH_QUEUE_SERIAL);
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        _lyricsText = nil;
        dispatch_sync(g_panels_queue, ^{
            CFArrayAppendValue(g_active_panels_cf, (__bridge void *)self);
        });
    }
    return self;
}

- (void)dealloc {
    dispatch_sync(g_panels_queue, ^{
        CFIndex idx = CFArrayGetFirstIndexOfValue(g_active_panels_cf,
            CFRangeMake(0, CFArrayGetCount(g_active_panels_cf)),
            (__bridge void *)self);
        if (idx != kCFNotFound) {
            CFArrayRemoveValueAtIndex(g_active_panels_cf, idx);
        }
    });
    [_lyricsText release];
    [super dealloc];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isFlipped {
    return YES;  // Y increases downward, matches text layout conventions
}

- (BOOL)hasLyrics {
    return _lyricsText != nil && _lyricsText.length > 0;
}

- (void)setLyricsText:(NSString *)text {
    // Must be called on the main thread (UI update).
    NSString *newText = (text.length > 0) ? [text retain] : nil;
    [_lyricsText release];
    _lyricsText = newText;
    [self setNeedsDisplay:YES];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // Dark background
    CGContextSetRGBFillColor(ctx, 0.1, 0.1, 0.1, 1.0);
    CGContextFillRect(ctx, NSRectToCGRect(dirtyRect));

    NSString *textToDraw = _lyricsText;
    BOOL hasContent = (textToDraw != nil && textToDraw.length > 0);

    if (!hasContent) {
        textToDraw = @"No lyrics loaded";
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: hasContent
            ? [NSColor colorWithWhite:0.9 alpha:1.0]
            : [NSColor colorWithWhite:0.6 alpha:1.0]
    };

    if (!hasContent) {
        // Centre the placeholder
        NSSize textSize = [textToDraw sizeWithAttributes:attrs];
        NSPoint origin = NSMakePoint(
            NSMidX(self.bounds) - textSize.width / 2.0,
            NSMidY(self.bounds) - textSize.height / 2.0
        );
        [textToDraw drawAtPoint:origin withAttributes:attrs];
    } else {
        // Draw lyrics top-left with padding; Task 5.1 will replace with Core Text
        NSRect textRect = NSInsetRect(self.bounds, 12.0, 12.0);
        [textToDraw drawInRect:textRect withAttributes:attrs];
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
            OpenLyricsView *v = (__bridge OpenLyricsView *)CFArrayGetValueAtIndex(g_active_panels_cf, i);
            if (v.window != nil) count++;
        }
    });
    return count;
}

void repaint_all_lyric_panels() {
    // Snapshot the array under the lock, then dispatch repaints without holding it.
    __block CFArrayRef snapshot = NULL;
    dispatch_sync(g_panels_queue, ^{
        snapshot = CFArrayCreateCopy(NULL, g_active_panels_cf);
    });
    CFIndex total = CFArrayGetCount(snapshot);
    for (CFIndex i = 0; i < total; i++) {
        OpenLyricsView *v = (__bridge OpenLyricsView *)CFArrayGetValueAtIndex(snapshot, i);
        dispatch_async(dispatch_get_main_queue(), ^{
            [v setNeedsDisplay:YES];
        });
    }
    CFRelease(snapshot);
}

// ---------------------------------------------------------------------------
// announce_lyric_update: called from LyricAutosearchManager's background thread
// when a search result arrives.  Store the lyrics, build plain text, push to
// all panels, and trigger a repaint — all marshalled to the main queue.
// ---------------------------------------------------------------------------

void announce_lyric_update(LyricUpdate update) {
    // Build plain text from lyrics lines (works for both synced and unsynced).
    std::string plain;
    plain.reserve(update.lyrics.lines.size() * 64);
    for (const LyricDataLine& line : update.lyrics.lines) {
        if (!plain.empty()) plain += '\n';
        plain += line.text;
    }
    NSString *text = [NSString stringWithUTF8String:plain.c_str()];

    // Move lyrics into global storage under the serial queue.
    LyricData captured = std::move(update.lyrics);
    dispatch_async(g_lyrics_queue, ^{
        g_current_lyrics = std::move(captured);
    });

    // Marshal to main thread for UI updates.
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_current_lyrics_text release];
        g_current_lyrics_text = [text retain];

        // Push text to every active panel.
        __block CFArrayRef snapshot = NULL;
        dispatch_sync(g_panels_queue, ^{
            snapshot = CFArrayCreateCopy(NULL, g_active_panels_cf);
        });
        CFIndex total = CFArrayGetCount(snapshot);
        for (CFIndex i = 0; i < total; i++) {
            OpenLyricsView *v = (__bridge OpenLyricsView *)CFArrayGetValueAtIndex(snapshot, i);
            [v setLyricsText:text];
        }
        CFRelease(snapshot);
    });
}
