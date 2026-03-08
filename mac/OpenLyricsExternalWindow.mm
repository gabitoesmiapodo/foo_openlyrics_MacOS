// mac/OpenLyricsExternalWindow.mm
// macOS implementation of SpawnExternalLyricWindow().
// Opens (or brings to front) a floating NSPanel containing an OpenLyricsView;
// a second call while the window is open closes it.
#include "stdafx.h"
#import "OpenLyricsView.h"

#include "../src/metrics.h"

// ---------------------------------------------------------------------------
// Persistence keys (NSUserDefaults)
// ---------------------------------------------------------------------------

static NSString * const kPrefExtWinX    = @"extwin.x";
static NSString * const kPrefExtWinY    = @"extwin.y";
static NSString * const kPrefExtWinW    = @"extwin.w";
static NSString * const kPrefExtWinH    = @"extwin.h";
static NSString * const kPrefExtWinOpen = @"extwin.wasOpen";

// ---------------------------------------------------------------------------
// OpenLyricsExternalWindowPanel
// ---------------------------------------------------------------------------

@interface OpenLyricsExternalWindowPanel : NSPanel <NSWindowDelegate>
@end

@implementation OpenLyricsExternalWindowPanel

- (BOOL)canBecomeKeyWindow  { return YES; }
- (BOOL)canBecomeMainWindow { return NO;  }

- (void)windowWillClose:(NSNotification *)notification {
    [self savePosition];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kPrefExtWinOpen];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)windowDidResize:(NSNotification *)notification {
    [self savePosition];
}

- (void)windowDidMove:(NSNotification *)notification {
    [self savePosition];
}

- (void)savePosition {
    NSRect frame = self.frame;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setDouble:frame.origin.x    forKey:kPrefExtWinX];
    [ud setDouble:frame.origin.y    forKey:kPrefExtWinY];
    [ud setDouble:frame.size.width  forKey:kPrefExtWinW];
    [ud setDouble:frame.size.height forKey:kPrefExtWinH];
}

@end

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------

static OpenLyricsExternalWindowPanel *g_external_panel = nil;

// ---------------------------------------------------------------------------
// SpawnExternalLyricWindow — toggle open / close
// ---------------------------------------------------------------------------

void SpawnExternalLyricWindow()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_external_panel != nil && [g_external_panel isVisible]) {
            [g_external_panel close];
            return;
        }

        metrics::log_used_external_window();

        if (g_external_panel == nil) {
            // Restore saved size; default to 640x640.
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            const CGFloat w = ([ud objectForKey:kPrefExtWinW] != nil)
                              ? [ud doubleForKey:kPrefExtWinW] : 640.0;
            const CGFloat h = ([ud objectForKey:kPrefExtWinH] != nil)
                              ? [ud doubleForKey:kPrefExtWinH] : 640.0;
            const CGFloat x = ([ud objectForKey:kPrefExtWinX] != nil)
                              ? [ud doubleForKey:kPrefExtWinX] : 100.0;
            const CGFloat y = ([ud objectForKey:kPrefExtWinY] != nil)
                              ? [ud doubleForKey:kPrefExtWinY] : 100.0;

            NSRect frame = NSMakeRect(x, y, w, h);

            const NSWindowStyleMask mask = NSWindowStyleMaskTitled
                                         | NSWindowStyleMaskClosable
                                         | NSWindowStyleMaskResizable
                                         | NSWindowStyleMaskMiniaturizable;

            g_external_panel = [[OpenLyricsExternalWindowPanel alloc]
                                 initWithContentRect:frame
                                           styleMask:mask
                                             backing:NSBackingStoreBuffered
                                               defer:NO];

            [g_external_panel setTitle:@"OpenLyrics"];
            [g_external_panel setDelegate:g_external_panel];
            [g_external_panel setFloatingPanel:YES];
            [g_external_panel setLevel:NSFloatingWindowLevel];
            [g_external_panel setReleasedWhenClosed:NO];

            OpenLyricsView *view = [[OpenLyricsView alloc]
                                    initWithFrame:frame];
            [g_external_panel setContentView:view];
            [view release];
        }

        [g_external_panel makeKeyAndOrderFront:nil];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrefExtWinOpen];
    });
}
