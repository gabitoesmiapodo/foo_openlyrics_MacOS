// mac/tests/OpenLyricsManualSearchTests.mm
// XCTest suite for the manual lyric search panel (Task 8.1).

#import <XCTest/XCTest.h>
#import "OpenLyricsManualSearch.h"

#ifdef __cplusplus
#include "../../src/lyric_data.h"
#endif

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

@interface OpenLyricsManualSearchTests : XCTestCase
@end

@implementation OpenLyricsManualSearchTests

- (void)testSearchPanelCreation
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertNotNil(panel, @"Search panel should be non-nil");
    [panel close];
    [panel release];
}

- (void)testSearchPanelHasArtistField
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertNotNil(panel.artistField, @"Panel must expose a non-nil artistField");
    [panel close];
    [panel release];
}

- (void)testSearchPanelHasAlbumField
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertNotNil(panel.albumField, @"Panel must expose a non-nil albumField");
    [panel close];
    [panel release];
}

- (void)testSearchPanelHasTitleField
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertNotNil(panel.titleField, @"Panel must expose a non-nil titleField");
    [panel close];
    [panel release];
}

- (void)testSearchPanelHasTableView
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertNotNil(panel.resultsTableView, @"Panel must expose a non-nil resultsTableView");
    [panel close];
    [panel release];
}

- (void)testSearchPanelHasStatusLabel
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertNotNil(panel.statusLabel, @"Panel must expose a non-nil statusLabel");
    [panel close];
    [panel release];
}

- (void)testSearchPanelWindowTitle
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    NSString *title = panel.window.title;
    XCTAssertTrue([title containsString:@"Search"],
                  @"Window title should contain 'Search', got: %@", title);
    [panel close];
    [panel release];
}

- (void)testSearchPanelWindowIsNSPanel
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    XCTAssertTrue([panel.window isKindOfClass:[NSPanel class]],
                  @"Search window should be an NSPanel");
    [panel close];
    [panel release];
}

- (void)testSearchPanelTableHasFiveColumns
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    NSInteger colCount = (NSInteger)panel.resultsTableView.tableColumns.count;
    XCTAssertEqual(colCount, 5,
                   @"Results table should have exactly 5 columns, got %ld", (long)colCount);
    [panel close];
    [panel release];
}

- (void)testSearchPanelInitialRowCount
{
    metadb_v2_rec_t info = {};
    OpenLyricsManualSearchPanel *panel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:nullptr
            trackInfo:info];
    NSInteger rows = [panel.resultsTableView numberOfRows];
    XCTAssertEqual(rows, 0, @"Table should start with 0 rows");
    [panel close];
    [panel release];
}

- (void)testSpawnManualSearchMacDoesNotCrash
{
    // In a test context without an active foobar2000 host this should be a no-op.
    if (!core_api::are_services_available()) {
        XCTAssertNoThrow(SpawnManualSearchMac(),
                         @"SpawnManualSearchMac should not throw in a test context");
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
}

@end
