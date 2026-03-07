// mac/OpenLyricsView.mm
#import "stdafx.h"
#import "OpenLyricsView.h"
#import <CoreText/CoreText.h>

#include "../src/ui_hooks.h"

static NSMutableArray<OpenLyricsView *> *g_active_panels;

@implementation OpenLyricsView

+ (void)initialize {
    if (self == [OpenLyricsView class]) {
        g_active_panels = [[NSMutableArray alloc] init];
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        [g_active_panels addObject:self];
    }
    return self;
}

- (void)dealloc {
    [g_active_panels removeObject:self];
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
    size_t count = 0;
    for (OpenLyricsView *v in g_active_panels) {
        if (v.window != nil) count++;
    }
    return count;
}

void repaint_all_lyric_panels() {
    for (OpenLyricsView *v in g_active_panels) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [v setNeedsDisplay:YES];
        });
    }
}

void announce_lyric_update(LyricUpdate update) {
    (void)update;
    repaint_all_lyric_panels();
}
