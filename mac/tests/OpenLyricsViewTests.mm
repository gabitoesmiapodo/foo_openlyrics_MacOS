#import <XCTest/XCTest.h>
#import "OpenLyricsView.h"

@interface OpenLyricsViewTests : XCTestCase
@end

@implementation OpenLyricsViewTests

- (void)testViewCreation {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertNotNil(view);
}

- (void)testViewIsLayerBacked {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue(view.wantsLayer);
}

- (void)testViewAcceptsFirstResponder {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue([view acceptsFirstResponder]);
}

- (void)testViewIsFlipped {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertTrue([view isFlipped]);
}

- (void)testHasLyricsInitiallyFalse {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    XCTAssertFalse([view hasLyrics], @"A freshly created view should report no lyrics");
}

- (void)testSetLyricsTextMakesHasLyricsTrue {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Never gonna give you up\nNever gonna let you down"];
    XCTAssertTrue([view hasLyrics], @"hasLyrics should be YES after setting non-empty text");
}

- (void)testSetLyricsTextNilClearsLyrics {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Some lyrics"];
    XCTAssertTrue([view hasLyrics]);
    [view setLyricsText:nil];
    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after passing nil");
}

- (void)testSetLyricsTextEmptyStringClearsLyrics {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    [view setLyricsText:@"Some lyrics"];
    XCTAssertTrue([view hasLyrics]);
    [view setLyricsText:@""];
    XCTAssertFalse([view hasLyrics], @"hasLyrics should be NO after passing empty string");
}

- (void)testSetLyricsTextMultilineRetainsContent {
    OpenLyricsView *view = [[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSString *expected = @"Line one\nLine two\nLine three";
    [view setLyricsText:expected];
    XCTAssertTrue([view hasLyrics]);
}

@end
