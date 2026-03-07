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

@end
