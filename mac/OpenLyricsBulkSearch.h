// mac/OpenLyricsBulkSearch.h
#pragma once

#ifdef __cplusplus
#include <vector>
#include "../src/lyric_data.h"
#endif

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

#ifdef __cplusplus

// Opens (or focuses) the bulk lyric search panel for the given tracks.
// Must be called on the main thread.
void SpawnBulkLyricSearchMac(std::vector<metadb_handle_ptr> tracks);

// NSWindowController managing the bulk lyric search panel.
@interface OpenLyricsBulkSearchPanel : NSWindowController <NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource>

// Designated initialiser. tracks may be empty in test contexts.
- (instancetype)initWithTracks:(const std::vector<metadb_handle_ptr>&)tracks NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithWindow:(NSWindow *)window NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// Add more tracks while the panel is running.
- (void)addTracks:(const std::vector<metadb_handle_ptr>&)tracks;

// UI exposed for tests.
@property (nonatomic, readonly) NSTableView        *resultsTableView;
@property (nonatomic, readonly) NSTextField        *statusLabel;
@property (nonatomic, readonly) NSProgressIndicator *progressIndicator;
@property (nonatomic, readonly) NSButton           *closeButton;

@end
#endif // __cplusplus

#endif // __OBJC__
