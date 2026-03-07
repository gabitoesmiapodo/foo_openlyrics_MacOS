// mac/OpenLyricsEditor.h
#pragma once

#ifdef __cplusplus
#include "../src/lyric_data.h"
#endif

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

// Opens (or focuses) the lyric editor for the currently playing track.
// Must be called on the main thread.
void SpawnLyricEditorMac(void);

#ifdef __cplusplus
// NSWindowController subclass managing the lyric editor panel.
@interface OpenLyricsEditorPanel : NSWindowController <NSWindowDelegate>

// Designated initialiser. Pass the LyricData to edit and the track handle.
// track may be nullptr in test contexts.
- (instancetype)initWithLyrics:(const LyricData&)lyrics
                         track:(metadb_handle_ptr)track
                    trackInfo:(const metadb_v2_rec_t&)trackInfo NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithWindow:(NSWindow *)window NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// The text view used for editing (exposed for tests).
@property (nonatomic, readonly) NSTextView *textView;

@end
#endif // __cplusplus

#endif // __OBJC__
