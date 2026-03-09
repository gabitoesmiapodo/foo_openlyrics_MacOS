// mac/OpenLyricsBulkSearch.mm
// Bulk lyric search panel — macOS port of ui_lyric_bulk_search.cpp.
#include "stdafx.h"

#import "OpenLyricsBulkSearch.h"

#include "../src/lyric_io.h"
#include "../src/lyric_metadata.h"
#include "../src/metrics.h"
#include "../src/tag_util.h"
#include "../src/logging.h"

// ---------------------------------------------------------------------------
// Column identifiers
// ---------------------------------------------------------------------------

static NSString* const kBulkColTitle  = @"Title";
static NSString* const kBulkColArtist = @"Artist";
static NSString* const kBulkColStatus = @"Status";

// ---------------------------------------------------------------------------
// Private interface with C++ ivars
// ---------------------------------------------------------------------------

@interface OpenLyricsBulkSearchPanel ()
{
    struct TrackRow
    {
        metadb_handle_ptr track;
        metadb_v2_rec_t   track_info;
        std::string       status;  // "", "Searching...", "Found", "Not found"
    };

    std::vector<TrackRow>                _rows;
    int                                  _nextSearchIndex;
    std::optional<LyricSearchHandle>     _childSearch;
    std::unique_ptr<abort_callback_impl> _childAbort;

    NSTableView*             _tableView;
    NSTextField*             _statusLabel;
    NSProgressIndicator*     _progressIndicator;
    NSButton*                _closeButton;
    NSTimer* __weak _pollTimer;
}
@end

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------

static OpenLyricsBulkSearchPanel* g_bulkSearchPanel = nil;

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation OpenLyricsBulkSearchPanel

@synthesize resultsTableView  = _tableView;
@synthesize statusLabel       = _statusLabel;
@synthesize progressIndicator = _progressIndicator;
@synthesize closeButton       = _closeButton;

- (instancetype)initWithTracks:(const std::vector<metadb_handle_ptr>&)tracks
{
    NSPanel* panel = [[[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 500, 420)
                  styleMask:NSWindowStyleMaskTitled
                           | NSWindowStyleMaskClosable
                           | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO] autorelease];
    [panel setTitle:@"Bulk Lyric Search"];
    [panel setReleasedWhenClosed:NO];
    [panel center];

    self = [super initWithWindow:panel];
    if (!self) return nil;

    _nextSearchIndex = 0;
    _childAbort = std::make_unique<abort_callback_impl>();

    [self buildUI];
    [panel setDelegate:self];

    [self addTracks:tracks];

    // Kick off polling if we have any tracks to process.
    if (!_rows.empty()) {
        [self schedulePollAfter:0.0];
    }

    return self;
}

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------

- (void)buildUI
{
    NSView*         content = [self.window contentView];
    const NSRect    bounds  = content.bounds;
    const CGFloat   M       = 12.0;   // margin
    const CGFloat   BH      = 24.0;   // button height
    const CGFloat   PH      = 16.0;   // progress bar height
    const CGFloat   SH      = 20.0;   // status label height

    // Cancel/Close button (bottom-right)
    _closeButton = [[NSButton alloc]
        initWithFrame:NSMakeRect(bounds.size.width - M - 80, M, 80, BH)];
    [_closeButton setTitle:@"Cancel"];
    [_closeButton setBezelStyle:NSBezelStyleRounded];
    [_closeButton setTarget:self];
    [_closeButton setAction:@selector(onClose:)];
    [_closeButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [content addSubview:_closeButton];
    [_closeButton release];

    // Progress bar
    const CGFloat progressY = M + BH + 6;
    _progressIndicator = [[NSProgressIndicator alloc]
        initWithFrame:NSMakeRect(M, progressY, bounds.size.width - 2*M, PH)];
    [_progressIndicator setStyle:NSProgressIndicatorStyleBar];
    [_progressIndicator setIndeterminate:NO];
    [_progressIndicator setMinValue:0.0];
    [_progressIndicator setMaxValue:1.0];
    [_progressIndicator setDoubleValue:0.0];
    [_progressIndicator setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:_progressIndicator];
    [_progressIndicator release];

    // Status label
    const CGFloat statusY = progressY + PH + 4;
    _statusLabel = [[NSTextField alloc]
        initWithFrame:NSMakeRect(M, statusY, bounds.size.width - 2*M, SH)];
    [_statusLabel setStringValue:@""];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:NO];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:_statusLabel];
    [_statusLabel release];

    // Scroll view + table
    const CGFloat tableBottom = statusY + SH + 6;
    NSScrollView* scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(M, tableBottom,
                                 bounds.size.width  - 2*M,
                                 bounds.size.height - tableBottom - M)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:NO];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setUsesAlternatingRowBackgroundColors:YES];
    [_tableView setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];

    NSTableColumn* titleCol = [[[NSTableColumn alloc] initWithIdentifier:kBulkColTitle] autorelease];
    [[titleCol headerCell] setStringValue:@"Title"];
    [titleCol setWidth:190.0];
    [titleCol setMinWidth:80.0];
    [_tableView addTableColumn:titleCol];

    NSTableColumn* artistCol = [[[NSTableColumn alloc] initWithIdentifier:kBulkColArtist] autorelease];
    [[artistCol headerCell] setStringValue:@"Artist"];
    [artistCol setWidth:144.0];
    [artistCol setMinWidth:60.0];
    [_tableView addTableColumn:artistCol];

    NSTableColumn* statusCol = [[[NSTableColumn alloc] initWithIdentifier:kBulkColStatus] autorelease];
    [[statusCol headerCell] setStringValue:@"Status"];
    [statusCol setWidth:80.0];
    [statusCol setMinWidth:60.0];
    [_tableView addTableColumn:statusCol];

    [scroll setDocumentView:_tableView];
    [content addSubview:scroll];
    [_tableView release];
}

// ---------------------------------------------------------------------------
// Track management
// ---------------------------------------------------------------------------

- (void)addTracks:(const std::vector<metadb_handle_ptr>&)newTracks
{
    if (newTracks.empty()) return;

    const size_t prevCount = _rows.size();
    const bool   wasDone   = (prevCount > 0)
                           && (_nextSearchIndex >= (int)prevCount)
                           && (_pollTimer == nil);

    for (const metadb_handle_ptr& handle : newTracks) {
        TrackRow row;
        row.track = handle;
        if (handle.is_valid() && core_api::are_services_available()) {
            row.track_info = get_full_metadata(handle);
        }
        row.status = "";
        _rows.push_back(std::move(row));
    }

    [_tableView beginUpdates];
    [_tableView insertRowsAtIndexes:
        [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(prevCount, _rows.size() - prevCount)]
                      withAnimation:NSTableViewAnimationEffectNone];
    [_tableView endUpdates];
    [_progressIndicator setMaxValue:(double)_rows.size()];

    if (wasDone) {
        // Resume from where we left off.
        _rows[_nextSearchIndex].status = "Searching...";
        [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:_nextSearchIndex]
                              columnIndexes:[NSIndexSet indexSetWithIndex:2]];
        [self schedulePollAfter:0.0];
    } else if (prevCount == 0) {
        // First batch — mark row 0 as "Searching..." (purely cosmetic while timer fires).
        _rows[0].status = "Searching...";
        [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:0]
                              columnIndexes:[NSIndexSet indexSetWithIndex:2]];
    }

    [self refreshStatusLabel];
}

// ---------------------------------------------------------------------------
// Poll timer
// ---------------------------------------------------------------------------

- (void)schedulePollAfter:(NSTimeInterval)delay
{
    [_pollTimer invalidate];
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                  target:self
                                                selector:@selector(onPollTimer:)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)onPollTimer:(NSTimer*)timer
{
    if (!core_api::are_services_available()) return;

    // No active search — start one for the current index.
    if (!_childSearch.has_value()) {
        if (_nextSearchIndex >= (int)_rows.size()) return;

        _childAbort->reset();
        TrackRow& row = _rows[_nextSearchIndex];
        _childSearch.emplace(LyricUpdate::Type::ManualSearch,
                             row.track, row.track_info, *_childAbort);
        io::search_for_lyrics(_childSearch.value(), false);
        [self schedulePollAfter:0.016];
        return;
    }

    LyricSearchHandle& handle = _childSearch.value();
    if (!handle.is_complete()) {
        [self schedulePollAfter:0.016];
        return;
    }

    const bool wereRemote = handle.has_searched_remote_sources();

    std::optional<LyricData> lyrics;
    if (handle.has_result()) {
        lyrics = io::process_available_lyric_update({
            handle.get_result(),
            handle.get_track(),
            handle.get_track_info(),
            handle.get_type()
        });
    }
    _childSearch.reset();

    if (lyrics.has_value()) {
        lyric_metadata_log_retrieved(_rows[_nextSearchIndex].track_info, lyrics.value());
    }

    const bool found = lyrics.has_value() && !lyrics.value().IsEmpty();
    _rows[_nextSearchIndex].status = found ? "Found" : "Not found";
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:_nextSearchIndex]
                          columnIndexes:[NSIndexSet indexSetWithIndex:2]];
    [_progressIndicator setDoubleValue:(double)(_nextSearchIndex + 1)];

    _nextSearchIndex++;

    if (_nextSearchIndex >= (int)_rows.size()) {
        [_statusLabel setStringValue:@"Done"];
        [_closeButton setTitle:@"Close"];
        return;
    }

    // Mark the next row as "Searching..." while we wait for the inter-search delay.
    // This keeps the UI looking active even during the 10-second remote-source cooldown.
    _rows[_nextSearchIndex].status = "Searching...";
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:_nextSearchIndex]
                          columnIndexes:[NSIndexSet indexSetWithIndex:2]];
    [self refreshStatusLabel];

    // NOTE: 10 s between remote searches to avoid flooding lyric servers.
    //       1 ms is enough when only local sources were consulted.
    const NSTimeInterval delay = wereRemote ? 10.0 : 0.001;
    [self schedulePollAfter:delay];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

- (void)refreshStatusLabel
{
    if (_nextSearchIndex >= (int)_rows.size()) {
        [_statusLabel setStringValue:@"Done"];
    } else {
        NSString* s = [NSString stringWithFormat:@"Searching %d/%zu",
                       _nextSearchIndex + 1, _rows.size()];
        [_statusLabel setStringValue:s];
    }
}

// ---------------------------------------------------------------------------
// Button action
// ---------------------------------------------------------------------------

- (void)onClose:(id)sender
{
    if (_childSearch.has_value()) {
        _childAbort->abort();
    }
    [self.window close];
}

// ---------------------------------------------------------------------------
// NSWindowDelegate
// ---------------------------------------------------------------------------

- (void)windowWillClose:(NSNotification*)notification
{
    [_pollTimer invalidate];
    _pollTimer = nil;

    if (g_bulkSearchPanel == self) {
        g_bulkSearchPanel = nil;
        [self release];
    }
}

// ---------------------------------------------------------------------------
// dealloc
// ---------------------------------------------------------------------------

- (void)dealloc
{
    [_pollTimer invalidate];
    _pollTimer = nil;

    if (_childSearch.has_value()) {
        _childAbort->abort();
        _childSearch.value().wait_for_complete(5000);
        _childSearch.reset();
    }

    [super dealloc];
}

// ---------------------------------------------------------------------------
// NSTableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return (NSInteger)_rows.size();
}

- (id)tableView:(NSTableView*)tableView
    objectValueForTableColumn:(NSTableColumn*)tableColumn
                          row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_rows.size()) return @"";

    const TrackRow& r = _rows[(size_t)row];
    NSString* col = tableColumn.identifier;

    if ([col isEqualToString:kBulkColTitle])
        return [NSString stringWithUTF8String:track_metadata(r.track_info, "title").c_str()];
    if ([col isEqualToString:kBulkColArtist])
        return [NSString stringWithUTF8String:track_metadata(r.track_info, "artist").c_str()];
    if ([col isEqualToString:kBulkColStatus])
        return [NSString stringWithUTF8String:r.status.c_str()];

    return @"";
}

@end

// ---------------------------------------------------------------------------
// Free function
// ---------------------------------------------------------------------------

void SpawnBulkLyricSearchMac(std::vector<metadb_handle_ptr> tracks)
{
    if (tracks.empty()) return;
    if (!core_api::are_services_available()) return;
    core_api::ensure_main_thread();

    if (g_bulkSearchPanel != nil) {
        [g_bulkSearchPanel addTracks:tracks];
        [[g_bulkSearchPanel window] makeKeyAndOrderFront:nil];
        return;
    }

    LOG_INFO("Spawning bulk search window...");
    metrics::log_used_bulk_search();

    OpenLyricsBulkSearchPanel* panel =
        [[OpenLyricsBulkSearchPanel alloc] initWithTracks:tracks];
    g_bulkSearchPanel = panel;  // ownership: alloc retains; windowWillClose: releases
    [panel showWindow:nil];
}
