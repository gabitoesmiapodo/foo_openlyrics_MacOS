#import <XCTest/XCTest.h>
#import "OpenLyricsView.h"

// C++ function under test (declared in OpenLyricsView.h when __cplusplus is defined)
#ifdef __cplusplus
void clear_all_lyric_panels();
#endif

@interface OpenLyricsViewTests : XCTestCase
@end

@implementation OpenLyricsViewTests

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
    XCTAssertTrue([view.currentLyricsText containsString:@"Line 1"] ||
                  [view.currentLyricsText containsString:@"Line one"],
                  @"currentLyricsText should contain the set content");
    [view release];
}

- (void)testClearAllLyricPanelsClearsRegisteredViews {
    // Create a view so it registers itself in the global panel list.
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Some lyrics to clear"];
    XCTAssertTrue([view hasLyrics], @"Precondition: view should have lyrics before clear");

    // clear_all_lyric_panels dispatches to the main queue; drain it.
    // dispatch_async to main queue posts a run-loop source, so run the loop
    // briefly to let it fire without relying on a wall-clock timer.
    clear_all_lyric_panels();
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, false);

    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after clear_all_lyric_panels");
    [view release];
}

@end
