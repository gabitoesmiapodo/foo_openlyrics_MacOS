// mac/OpenLyricsView.h
#pragma once

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

@interface OpenLyricsView : NSView

- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Returns YES if lyrics have been loaded (non-empty line count).
- (BOOL)hasLyrics;

/// Returns the current plain-text lyrics string, or nil if none are loaded.
- (NSString *)currentLyricsText;

/// Sets plain-text lyrics for display.  Pass nil or empty string to clear.
/// This method is the bridge between C++ LyricData and the ObjC view layer.
- (void)setLyricsText:(NSString *)text;

@end

#endif // __OBJC__

#ifdef __cplusplus
/// Clears lyrics on all active panels. Safe to call from any thread
/// (dispatches to the main queue internally).
void clear_all_lyric_panels();
#endif
