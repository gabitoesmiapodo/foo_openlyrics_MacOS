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

#ifdef __cplusplus
/// Returns a copy of the current LyricData (for the lyric editor).
- (LyricData)currentLyricData;
#endif

@end

#endif // __OBJC__

#ifdef __cplusplus
/// Repaints all active panels (dispatches to main queue).
void repaint_all_lyric_panels();

/// Recomputes background images then repaints all active panels (dispatches to main queue).
void recompute_lyric_panel_backgrounds();

/// Clears lyrics on all active panels. Safe to call from any thread.
void clear_all_lyric_panels();

/// Called when a lyric search result arrives (any thread).
void announce_lyric_update(LyricUpdate update);

/// Called on new track to set the now-playing state on all panels (any thread).
void set_now_playing_track(metadb_handle_ptr track, metadb_v2_rec_t info);

/// Returns a copy of the LyricData from the first active panel that has lyrics.
/// Sets out_track and out_info from the currently-playing track if available.
/// Must be called on the main thread.
LyricData get_active_panel_lyrics(metadb_handle_ptr& out_track, metadb_v2_rec_t& out_info);
#endif
