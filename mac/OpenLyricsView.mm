// mac/OpenLyricsView.mm
#import "stdafx.h"
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

#include "../src/ui_hooks.h"

static CFMutableArrayRef g_active_panels_cf;
static dispatch_queue_t g_panels_queue;

@implementation OpenLyricsView

+ (void)initialize {
    if (self == [OpenLyricsView class]) {
        CFArrayCallBacks weakCallbacks = kCFTypeArrayCallBacks;
        weakCallbacks.retain = NULL;
        weakCallbacks.release = NULL;
        g_active_panels_cf = CFArrayCreateMutable(NULL, 0, &weakCallbacks);
        g_panels_queue = dispatch_queue_create("com.foo_openlyrics.panels", DISPATCH_QUEUE_SERIAL);
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
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
    [super dealloc];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isFlipped {
    return YES;  // Y increases downward, matches text layout conventions
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

    // "No lyrics loaded" centered
    NSString *message = @"No lyrics loaded";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.6 alpha:1.0]
    };
    NSSize textSize = [message sizeWithAttributes:attrs];
    NSPoint origin = NSMakePoint(
        NSMidX(self.bounds) - textSize.width / 2.0,
        NSMidY(self.bounds) - textSize.height / 2.0
    );
    [message drawAtPoint:origin withAttributes:attrs];
}

@end

// ---- Panel hook implementations (replaces stubs in MacStubs.mm) ----

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

void announce_lyric_update(LyricUpdate update) {
    // TODO(Task 5.1): store update.lyrics in the view before repainting
    (void)update;
    repaint_all_lyric_panels();
}
