// mac/tests/OpenLyricsEditorTests.mm
// XCTest suite for the lyric editor panel (Task 7.1).

#import <XCTest/XCTest.h>
#import "OpenLyricsEditor.h"
#import "OpenLyricsView.h"

#ifdef __cplusplus
#include "../../src/lyric_data.h"
#endif

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static LyricData make_empty_lyrics() {
    return LyricData();
}

static LyricData make_unsynced_lyrics_ed(NSArray<NSString *> *lines) {
    LyricData data;
    for (NSString *line in lines) {
        LyricDataLine dl;
        dl.text = std::string([line UTF8String]);
        dl.timestamp = DBL_MAX;
        data.lines.push_back(dl);
    }
    return data;
}

static LyricData make_synced_lyrics_ed(NSArray<NSString *> *lines) {
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

@interface OpenLyricsEditorTests : XCTestCase
@end

@implementation OpenLyricsEditorTests

- (void)testEditorPanelCreationWithEmptyLyrics {
    LyricData empty = make_empty_lyrics();
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:empty
                 track:nullptr
             trackInfo:info];
    XCTAssertNotNil(panel, @"Editor panel should be non-nil even with empty lyrics");
    [panel close];
    [panel release];
}

- (void)testEditorPanelCreationWithUnsyncedLyrics {
    LyricData lyrics = make_unsynced_lyrics_ed(@[@"Line one", @"Line two", @"Line three"]);
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:nullptr
             trackInfo:info];
    XCTAssertNotNil(panel);
    [panel close];
    [panel release];
}

- (void)testEditorPanelCreationWithSyncedLyrics {
    LyricData lyrics = make_synced_lyrics_ed(@[@"First", @"Second", @"Third"]);
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:nullptr
             trackInfo:info];
    XCTAssertNotNil(panel);
    [panel close];
    [panel release];
}

- (void)testEditorHasTextView {
    LyricData lyrics = make_unsynced_lyrics_ed(@[@"Hello world"]);
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:nullptr
             trackInfo:info];
    XCTAssertNotNil(panel.textView, @"Editor panel must expose a non-nil textView");
    [panel close];
    [panel release];
}

- (void)testEditorTextViewContainsLyrics {
    LyricData lyrics = make_unsynced_lyrics_ed(@[@"Never gonna give you up", @"Never gonna let you down"]);
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:nullptr
             trackInfo:info];

    NSString *text = [panel.textView string];
    XCTAssertTrue([text containsString:@"Never gonna give you up"],
                  @"Text view should contain the lyrics lines");
    XCTAssertTrue([text containsString:@"Never gonna let you down"],
                  @"Text view should contain the lyrics lines");

    [panel close];
    [panel release];
}

- (void)testEditorWindowIsNSPanel {
    LyricData empty = make_empty_lyrics();
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:empty
                 track:nullptr
             trackInfo:info];

    XCTAssertTrue([panel.window isKindOfClass:[NSPanel class]],
                  @"Editor window should be an NSPanel");

    [panel close];
    [panel release];
}

- (void)testEditorWindowHasTitle {
    LyricData empty = make_empty_lyrics();
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:empty
                 track:nullptr
             trackInfo:info];

    XCTAssertEqualObjects(panel.window.title, @"Lyric Editor",
                          @"Editor window title should be 'Lyric Editor'");

    [panel close];
    [panel release];
}

- (void)testSpawnLyricEditorMacDoesNotCrash {
    // In a test context with no active foobar2000 services this should be a no-op
    // or open an empty editor window without crashing.
    XCTAssertNoThrow(SpawnLyricEditorMac(),
                     @"SpawnLyricEditorMac should not throw or crash in a test context");

    // Clean up any window that may have been opened
    // Give the run loop a moment to process
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
}

- (void)testSyncedLyricsDisplayWithTimestamps {
    LyricData lyrics = make_synced_lyrics_ed(@[@"Intro line", @"Main verse"]);
    metadb_v2_rec_t info = {};
    OpenLyricsEditorPanel *panel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:nullptr
             trackInfo:info];

    NSString *text = [panel.textView string];
    // Synced lyrics should be rendered with [mm:ss.xx] timestamps via expand_text
    XCTAssertTrue([text containsString:@"["],
                  @"Synced lyrics should produce LRC-style bracket timestamps in the editor");

    [panel close];
    [panel release];
}

@end
