// mac/OpenLyricsView.h
#pragma once

// lyric_data.h must come before the ObjC @interface so LyricData is visible
// in both C++ and ObjC++ translation units.
#ifdef __cplusplus
#include "../src/lyric_data.h"
#include "../src/lyric_io.h"
#endif

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

@interface OpenLyricsView : NSView

- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Returns YES if lyrics have been loaded (non-empty line count).
- (BOOL)hasLyrics;

/// Returns the current plain-text lyrics string (all lines joined by newline), or nil if none.
/// Kept for tests.
- (NSString *)currentLyricsText;

#ifdef __cplusplus
/// Updates the view with new LyricData. Starts scroll timer if lyrics are timestamped.
- (void)updateLyrics:(const LyricData&)lyrics;
#endif

/// Clears lyrics and stops the scroll timer.
- (void)clearLyrics;

/// Returns YES if the scroll timer is currently running (i.e. synced lyrics are loaded).
- (BOOL)isTimerRunning;

/// Legacy plain-text setter kept for test compatibility.
- (void)setLyricsText:(NSString *)text;

@end

#endif // __OBJC__

#ifdef __cplusplus
/// Repaints all active panels (dispatches to main queue).
void repaint_all_lyric_panels();

/// Clears lyrics on all active panels. Safe to call from any thread.
void clear_all_lyric_panels();

/// Called when a lyric search result arrives (any thread).
void announce_lyric_update(LyricUpdate update);
#endif
