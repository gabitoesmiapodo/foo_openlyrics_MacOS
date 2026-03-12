// mac/OpenLyricsManualSearch.h
#pragma once

#ifdef __cplusplus
#include "../src/lyric_data.h"
#endif

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

// Opens (or focuses) the manual lyric search panel for the currently playing track.
// Must be called on the main thread.
void SpawnManualSearchMac(void);

#ifdef __cplusplus
// Opens the manual lyric search panel for a specific track (e.g. from playlist context menu).
// May be called from any thread; will dispatch to main thread if needed.
void SpawnManualSearchMacForTrack(metadb_handle_ptr track, const metadb_v2_rec_t& info);

// NSWindowController managing the manual lyric search panel.
@interface OpenLyricsManualSearchPanel : NSWindowController <NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource>

// Designated initialiser. Pass the track handle and metadata.
// track may be nullptr in test contexts.
- (instancetype)initWithTrack:(metadb_handle_ptr)track
                    trackInfo:(const metadb_v2_rec_t&)info NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithWindow:(NSWindow *)window NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// UI fields exposed for tests.
@property (nonatomic, readonly) NSTextField *artistField;
@property (nonatomic, readonly) NSTextField *albumField;
@property (nonatomic, readonly) NSTextField *titleField;
@property (nonatomic, readonly) NSTableView *resultsTableView;
@property (nonatomic, readonly) NSTextField *statusLabel;

@end
#endif // __cplusplus

#endif // __OBJC__
