// mac/tests/OpenLyricsBulkSearchTests.mm
// XCTest suite for the bulk lyric search panel (Task 8.2).

#import <XCTest/XCTest.h>
#import "OpenLyricsBulkSearch.h"

#ifdef __cplusplus
#include "../../src/lyric_data.h"
#endif

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

@interface OpenLyricsBulkSearchTests : XCTestCase
@end

@implementation OpenLyricsBulkSearchTests

- (void)testBulkSearchPanelCreation
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    XCTAssertNotNil(panel, @"Bulk search panel should be non-nil");
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelHasTableView
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    XCTAssertNotNil(panel.resultsTableView, @"Panel must expose a non-nil resultsTableView");
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelHasStatusLabel
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    XCTAssertNotNil(panel.statusLabel, @"Panel must expose a non-nil statusLabel");
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelHasProgressIndicator
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    XCTAssertNotNil(panel.progressIndicator,
                    @"Panel must expose a non-nil progressIndicator");
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelHasCloseButton
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    XCTAssertNotNil(panel.closeButton, @"Panel must expose a non-nil closeButton");
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelWindowTitle
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    NSString *title = panel.window.title;
    XCTAssertTrue([title containsString:@"Bulk"],
                  @"Window title should contain 'Bulk', got: %@", title);
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelWindowIsNSPanel
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    XCTAssertTrue([panel.window isKindOfClass:[NSPanel class]],
                  @"Bulk search window should be an NSPanel");
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelTableHasThreeColumns
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    NSInteger colCount = (NSInteger)panel.resultsTableView.tableColumns.count;
    XCTAssertEqual(colCount, 3,
                   @"Results table should have exactly 3 columns, got %ld", (long)colCount);
    [panel close];
    [panel release];
}

- (void)testBulkSearchPanelInitialRowCount
{
    std::vector<metadb_handle_ptr> tracks;
    OpenLyricsBulkSearchPanel *panel = [[OpenLyricsBulkSearchPanel alloc]
        initWithTracks:tracks];
    NSInteger rows = [panel.resultsTableView numberOfRows];
    XCTAssertEqual(rows, 0, @"Table should start with 0 rows when no tracks given");
    [panel close];
    [panel release];
}

- (void)testSpawnBulkLyricSearchMacDoesNotCrash
{
    // Empty list: always a no-op.
    std::vector<metadb_handle_ptr> empty;
    XCTAssertNoThrow(SpawnBulkLyricSearchMac(empty),
                     @"SpawnBulkLyricSearchMac with empty list should not throw");

    // In a test context without an active foobar2000 host this should be a no-op.
    if (!core_api::are_services_available()) {
        std::vector<metadb_handle_ptr> tracks = { metadb_handle_ptr{} };
        XCTAssertNoThrow(SpawnBulkLyricSearchMac(tracks),
                         @"SpawnBulkLyricSearchMac should not throw in test context");
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
}

@end
