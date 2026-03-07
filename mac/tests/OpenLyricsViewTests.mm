#import <XCTest/XCTest.h>
#import "OpenLyricsView.h"

// C++ function under test (declared in OpenLyricsView.h when __cplusplus is defined)
#ifdef __cplusplus
#include "../../src/lyric_data.h"
void clear_all_lyric_panels();
#endif

// Helper: build a LyricData with plain (unsynced) lines.
static LyricData make_unsynced_lyrics(NSArray<NSString *> *lines) {
    LyricData data;
    for (NSString *line in lines) {
        LyricDataLine dl;
        dl.text = std::string([line UTF8String]);
        dl.timestamp = DBL_MAX; // unsynced
        data.lines.push_back(dl);
    }
    return data;
}

// Helper: build a LyricData with timestamped (synced) lines.
static LyricData make_synced_lyrics(NSArray<NSString *> *lines) {
    LyricData data;
    double ts = 1.0;
    for (NSString *line in lines) {
        LyricDataLine dl;
        dl.text = std::string([line UTF8String]);
        dl.timestamp = ts;
        ts += 3.0;
        data.lines.push_back(dl);
    }
    return data;
}

@interface OpenLyricsViewTests : XCTestCase
@end

@implementation OpenLyricsViewTests

// ---------------------------------------------------------------------------
// Existing tests (preserved)
// ---------------------------------------------------------------------------

- (void)testViewCreation {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertNotNil(view);
    [view release];
}

- (void)testViewIsLayerBacked {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue(view.wantsLayer);
    [view release];
}

- (void)testViewAcceptsFirstResponder {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue([view acceptsFirstResponder]);
    [view release];
}

- (void)testViewIsFlipped {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue([view isFlipped]);
    [view release];
}

- (void)testHasLyricsInitiallyFalse {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertFalse([view hasLyrics], @"A freshly created view should report no lyrics");
    [view release];
}

- (void)testSetLyricsTextMakesHasLyricsTrue {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Never gonna give you up\nNever gonna let you down"];
    XCTAssertTrue([view hasLyrics], @"hasLyrics should be YES after setting non-empty text");
    [view release];
}

- (void)testSetLyricsTextNilClearsLyrics {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Some lyrics"];
    XCTAssertTrue([view hasLyrics]);
    [view setLyricsText:nil];
    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after passing nil");
    [view release];
}

- (void)testSetLyricsTextEmptyStringClearsLyrics {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Some lyrics"];
    XCTAssertTrue([view hasLyrics]);
    [view setLyricsText:@""];
    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after passing empty string");
    [view release];
}

- (void)testSetLyricsTextMultilineRetainsContent {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSString *expected = @"Line one\nLine two\nLine three";
    [view setLyricsText:expected];
    XCTAssertTrue([view hasLyrics]);
    XCTAssertTrue([view.currentLyricsText containsString:@"Line one"],
                  @"currentLyricsText should contain the set content");
    [view release];
}

- (void)testClearAllLyricPanelsClearsRegisteredViews {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Some lyrics to clear"];
    XCTAssertTrue([view hasLyrics], @"Precondition: view should have lyrics before clear");

    clear_all_lyric_panels();
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, false);

    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after clear_all_lyric_panels");
    [view release];
}

// ---------------------------------------------------------------------------
// New Core Text / synced scrolling tests
// ---------------------------------------------------------------------------

- (void)testUpdateLyricsPopulatesView {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_unsynced_lyrics(@[@"Hello world", @"Second line"]);
    [view updateLyrics:data];
    XCTAssertTrue([view hasLyrics], @"hasLyrics should be YES after updateLyrics: with lines");
    [view release];
}

- (void)testClearLyricsMakesEmpty {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_unsynced_lyrics(@[@"Some line"]);
    [view updateLyrics:data];
    XCTAssertTrue([view hasLyrics], @"Precondition: should have lyrics");
    [view clearLyrics];
    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after clearLyrics");
    [view release];
}

- (void)testSyncedLyricsStartsTimer {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_synced_lyrics(@[@"Line one", @"Line two", @"Line three"]);
    [view updateLyrics:data];
    XCTAssertTrue([view isTimerRunning],
                  @"Scroll timer should be running after setting timestamped lyrics");
    [view release];
}

- (void)testUnsyncedLyricsDoesNotStartTimer {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_unsynced_lyrics(@[@"Line one", @"Line two"]);
    [view updateLyrics:data];
    XCTAssertFalse([view isTimerRunning],
                   @"Scroll timer should NOT run for unsynced lyrics");
    [view release];
}

- (void)testClearStopsTimer {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_synced_lyrics(@[@"Line one", @"Line two"]);
    [view updateLyrics:data];
    XCTAssertTrue([view isTimerRunning], @"Precondition: timer should be running");
    [view clearLyrics];
    XCTAssertFalse([view isTimerRunning],
                   @"Scroll timer should be stopped after clearLyrics");
    [view release];
}

- (void)testUpdateLyricsCurrentLyricsTextMatchesLines {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_unsynced_lyrics(@[@"Never gonna give you up", @"Never gonna let you down"]);
    [view updateLyrics:data];
    NSString *text = [view currentLyricsText];
    XCTAssertTrue([text containsString:@"Never gonna give you up"]);
    XCTAssertTrue([text containsString:@"Never gonna let you down"]);
    [view release];
}

// ---------------------------------------------------------------------------
// Context menu tests
// ---------------------------------------------------------------------------

- (void)testMenuForEventReturnsNonNilMenu {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSMenu *menu = [view menuForEvent:nil];
    XCTAssertNotNil(menu, @"menuForEvent: should return a non-nil NSMenu");
    [view release];
}

- (void)testMenuCopyLyricsDisabledWhenNoLyrics {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSMenu *menu = [view menuForEvent:nil];
    NSMenuItem *copyItem = [menu itemWithTitle:@"Copy Lyrics"];
    XCTAssertNotNil(copyItem, @"Copy Lyrics item should exist in the menu");
    XCTAssertFalse(copyItem.isEnabled, @"Copy Lyrics should be disabled when no lyrics are loaded");
    [view release];
}

- (void)testMenuCopyLyricsEnabledWhenHasLyrics {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    LyricData data = make_unsynced_lyrics(@[@"Some lyric line"]);
    [view updateLyrics:data];
    NSMenu *menu = [view menuForEvent:nil];
    NSMenuItem *copyItem = [menu itemWithTitle:@"Copy Lyrics"];
    XCTAssertNotNil(copyItem, @"Copy Lyrics item should exist in the menu");
    XCTAssertTrue(copyItem.isEnabled, @"Copy Lyrics should be enabled when lyrics are loaded");
    [view release];
}

@end
