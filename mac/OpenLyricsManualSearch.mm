// mac/OpenLyricsManualSearch.mm
// Manual lyric search panel for the macOS foo_openlyrics port.
// Provides an NSPanel-based dialog mirroring the upstream Windows ManualLyricSearch dialog.

#import "stdafx.h"
#import "OpenLyricsManualSearch.h"
#import "OpenLyricsView.h"

#include "../src/lyric_io.h"
#include "../src/logging.h"
#include "../src/parsers.h"
#include "../src/tag_util.h"
#include "../src/ui_hooks.h"
#include "../src/sources/lyric_source.h"

#include <vector>
#include <list>

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------

static OpenLyricsManualSearchPanel* g_searchPanel = nil;

// ---------------------------------------------------------------------------
// Column identifiers
// ---------------------------------------------------------------------------

static NSString * const kColTitle       = @"title";
static NSString * const kColArtist      = @"artist";
static NSString * const kColAlbum       = @"album";
static NSString * const kColSource      = @"source";
static NSString * const kColTimestamped = @"timestamped";

// ---------------------------------------------------------------------------
// OpenLyricsManualSearchPanel
// ---------------------------------------------------------------------------

@interface OpenLyricsManualSearchPanel () {
    metadb_handle_ptr  _track;
    metadb_v2_rec_t    _trackInfo;

    // Search state — all access on main thread via poll timer
    std::vector<LyricData>             _allLyrics;
    std::optional<LyricSearchHandle>   _childSearch;
    // Use unique_ptr so we can replace it for each new search (abort_callback_impl is not copyable/assignable)
    std::unique_ptr<abort_callback_impl> _childAbort;

    // UI
    NSTextField   *_artistField;
    NSTextField   *_albumField;
    NSTextField   *_titleField;
    NSTextField   *_statusLabel;
    NSButton      *_btnSearch;
    NSTableView   *_tableView;
    NSScrollView  *_tableScroll;
    NSTextView    *_previewText;
    NSScrollView  *_previewScroll;
    NSButton      *_btnApply;
    NSButton      *_btnCancel;

    NSTimer       *_pollTimer;
}

@property (nonatomic, readwrite) NSTextField *artistField;
@property (nonatomic, readwrite) NSTextField *albumField;
@property (nonatomic, readwrite) NSTextField *titleField;
@property (nonatomic, readwrite) NSTableView *resultsTableView;
@property (nonatomic, readwrite) NSTextField *statusLabel;

- (void)buildUI;
- (NSButton *)makeButton:(NSString *)title action:(SEL)action frame:(NSRect)frame;
- (NSTextField *)makeLabelField:(NSString *)text frame:(NSRect)frame;
- (NSTextField *)makeEditField:(NSString *)placeholder frame:(NSRect)frame;
- (void)startSearch;
- (void)applySelected;
- (void)stopPollTimer;
- (void)onPollTimer:(NSTimer *)timer;

@end

@implementation OpenLyricsManualSearchPanel

@synthesize artistField      = _artistField;
@synthesize albumField       = _albumField;
@synthesize titleField       = _titleField;
@synthesize resultsTableView = _tableView;
@synthesize statusLabel      = _statusLabel;

- (instancetype)initWithCoder:(NSCoder *)coder
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTrack:(metadb_handle_ptr)track
                    trackInfo:(const metadb_v2_rec_t&)info
{
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 740, 580)
                  styleMask:(NSWindowStyleMaskTitled    |
                             NSWindowStyleMaskClosable  |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [panel setTitle:@"Manual Lyric Search"];
    [panel setFloatingPanel:NO];
    [panel center];

    self = [super initWithWindow:panel];
    [panel release];

    if (self) {
        _track      = track;
        _trackInfo  = info;
        _childAbort = std::make_unique<abort_callback_impl>();

        [self buildUI];

        // Pre-fill fields from track metadata
        std::string artist = track_metadata(_trackInfo, "artist");
        std::string album  = track_metadata(_trackInfo, "album");
        std::string title  = track_metadata(_trackInfo, "title");

        if (!artist.empty())
            [_artistField setStringValue:[NSString stringWithUTF8String:artist.c_str()]];
        if (!album.empty())
            [_albumField  setStringValue:[NSString stringWithUTF8String:album.c_str()]];
        if (!title.empty())
            [_titleField  setStringValue:[NSString stringWithUTF8String:title.c_str()]];

        self.window.delegate = self;
    }
    return self;
}

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------

- (void)buildUI
{
    NSView *content = self.window.contentView;
    const CGFloat W = 740;

    // ---- Bottom buttons ------------------------------------------------
    const CGFloat btnH = 26;
    const CGFloat btnW = 80;
    const CGFloat gap  = 8;
    const CGFloat bY   = 8;

    _btnCancel = [self makeButton:@"Cancel"
                           action:@selector(onCancel:)
                            frame:NSMakeRect(W - btnW - 10, bY, btnW, btnH)];
    [content addSubview:_btnCancel];

    _btnApply = [self makeButton:@"Apply"
                          action:@selector(onApply:)
                           frame:NSMakeRect(W - btnW*2 - gap - 10, bY, btnW, btnH)];
    [_btnApply setEnabled:NO];
    [content addSubview:_btnApply];

    // ---- Status label --------------------------------------------------
    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, bY + 4, W - btnW*2 - gap*2 - 20, 18)];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:NO];
    [_statusLabel setStringValue:@""];
    [_statusLabel setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:_statusLabel];
    [_statusLabel release];

    // ---- Preview area --------------------------------------------------
    const CGFloat previewH = 110;
    const CGFloat previewY = bY + btnH + gap + 4;

    NSTextField *previewLabel = [self makeLabelField:@"Preview:"
                                               frame:NSMakeRect(10, previewY + previewH + 2, 60, 16)];
    [content addSubview:previewLabel];

    _previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, previewY, W - 20, previewH)];
    [_previewScroll setHasVerticalScroller:YES];
    [_previewScroll setHasHorizontalScroller:NO];
    [_previewScroll setBorderType:NSBezelBorder];
    [_previewScroll setAutoresizingMask:NSViewWidthSizable];

    _previewText = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, W - 20, previewH)];
    [_previewText setEditable:NO];
    [_previewText setSelectable:YES];
    [_previewText setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_previewText setMinSize:NSMakeSize(0, previewH)];
    [_previewText setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [_previewText setVerticallyResizable:YES];
    [_previewText setHorizontallyResizable:NO];
    [_previewText setAutoresizingMask:NSViewWidthSizable];
    [_previewText textContainer].widthTracksTextView = YES;

    [_previewScroll setDocumentView:_previewText];
    [content addSubview:_previewScroll];
    [_previewText release];
    [_previewScroll release];

    // ---- Results table -------------------------------------------------
    const CGFloat searchRowH = 32;
    const CGFloat topMargin  = 8;
    // We place the search row at the top, table fills the middle.
    // Layout from top (high Y) down in flipped or from bottom (low Y) up in non-flipped.
    // NSView uses bottom-left origin; H = window height.
    const CGFloat windowH   = 580;
    const CGFloat searchY   = windowH - searchRowH - topMargin;
    const CGFloat tableTop  = previewY + previewH + 22;
    const CGFloat tableH    = searchY - tableTop - 4;

    _tableScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, tableTop, W - 20, tableH)];
    [_tableScroll setHasVerticalScroller:YES];
    [_tableScroll setHasHorizontalScroller:YES];
    [_tableScroll setBorderType:NSBezelBorder];
    [_tableScroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 20, tableH)];
    [_tableView setAllowsMultipleSelection:NO];
    [_tableView setAllowsEmptySelection:YES];
    [_tableView setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [_tableView setDelegate:self];
    [_tableView setDataSource:self];
    [_tableView setDoubleAction:@selector(onDoubleClick:)];
    [_tableView setTarget:self];
    [_tableView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    struct ColSpec { NSString *id; NSString *title; CGFloat width; };
    ColSpec cols[] = {
        { kColTitle,       @"Title",       160 },
        { kColArtist,      @"Artist",      128 },
        { kColAlbum,       @"Album",       128 },
        { kColSource,      @"Source",       96 },
        { kColTimestamped, @"Timestamped",  80 },
    };
    for (int i = 0; i < 5; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].id];
        [col setTitle:cols[i].title];
        [col setWidth:cols[i].width];
        [col setMinWidth:32];
        [col setResizingMask:NSTableColumnUserResizingMask];
        [_tableView addTableColumn:col];
        [col release];
    }

    [_tableScroll setDocumentView:_tableView];
    [content addSubview:_tableScroll];
    [_tableView release];
    [_tableScroll release];

    // ---- Search row (top of window) ------------------------------------
    const CGFloat labelW = 50;
    const CGFloat fieldW = 155;
    CGFloat x = 10;
    CGFloat rowY = searchY + 4;

    [content addSubview:[self makeLabelField:@"Artist:"
                                       frame:NSMakeRect(x, rowY, labelW, 20)]];
    x += labelW + 2;
    _artistField = [self makeEditField:@"Artist" frame:NSMakeRect(x, rowY - 2, fieldW, 22)];
    [content addSubview:_artistField];
    x += fieldW + gap;

    [content addSubview:[self makeLabelField:@"Album:"
                                       frame:NSMakeRect(x, rowY, labelW, 20)]];
    x += labelW + 2;
    _albumField = [self makeEditField:@"Album" frame:NSMakeRect(x, rowY - 2, fieldW, 22)];
    [content addSubview:_albumField];
    x += fieldW + gap;

    [content addSubview:[self makeLabelField:@"Title:"
                                       frame:NSMakeRect(x, rowY, labelW, 20)]];
    x += labelW + 2;
    _titleField = [self makeEditField:@"Title" frame:NSMakeRect(x, rowY - 2, fieldW, 22)];
    [content addSubview:_titleField];
    x += fieldW + gap;

    _btnSearch = [self makeButton:@"Search"
                           action:@selector(onSearch:)
                            frame:NSMakeRect(x, rowY - 2, 70, 24)];
    [content addSubview:_btnSearch];
}

- (NSButton *)makeButton:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
    NSButton *btn = [[NSButton alloc] initWithFrame:frame];
    [btn setTitle:title];
    [btn setTarget:self];
    [btn setAction:action];
    [btn setBezelStyle:NSBezelStyleRounded];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    return [btn autorelease];
}

- (NSTextField *)makeLabelField:(NSString *)text frame:(NSRect)frame
{
    NSTextField *f = [[NSTextField alloc] initWithFrame:frame];
    [f setBezeled:NO];
    [f setDrawsBackground:NO];
    [f setEditable:NO];
    [f setSelectable:NO];
    [f setStringValue:text];
    [f setFont:[NSFont systemFontOfSize:NSFont.systemFontSize]];
    [f setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    return [f autorelease];
}

- (NSTextField *)makeEditField:(NSString *)placeholder frame:(NSRect)frame
{
    NSTextField *f = [[NSTextField alloc] initWithFrame:frame];
    [f setPlaceholderString:placeholder];
    [f setBezelStyle:NSTextFieldSquareBezel];
    [f setBezeled:YES];
    [f setEditable:YES];
    [f setSelectable:YES];
    [f setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    return [f autorelease];
}

// ---------------------------------------------------------------------------
// Dealloc
// ---------------------------------------------------------------------------

- (void)dealloc
{
    [self stopPollTimer];
    if (_childAbort) _childAbort->abort();
    if (_childSearch.has_value()) {
        _childSearch.value().wait_for_complete(5000);
        _childSearch.reset();
    }
    [super dealloc];
}

// ---------------------------------------------------------------------------
// NSWindowDelegate
// ---------------------------------------------------------------------------

- (void)windowWillClose:(NSNotification *)notification
{
    [self stopPollTimer];
    if (_childAbort) _childAbort->abort();

    if (g_searchPanel == self) {
        g_searchPanel = nil;
        [self release];
    }
}

// ---------------------------------------------------------------------------
// Button actions
// ---------------------------------------------------------------------------

- (void)onSearch:(id)sender
{
    [self startSearch];
}

- (void)onApply:(id)sender
{
    [self applySelected];
}

- (void)onCancel:(id)sender
{
    [self.window close];
}

- (void)onDoubleClick:(id)sender
{
    [self applySelected];
    [self.window close];
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

- (void)startSearch
{
    // Reset UI
    [_statusLabel setStringValue:@"Searching..."];
    [_tableView deselectAll:nil];
    _allLyrics.clear();
    [_tableView reloadData];
    [_previewText setString:@""];
    [_btnApply setEnabled:NO];
    [self stopPollTimer];

    // Replace abort callback so the new search gets a fresh one
    if (_childAbort) _childAbort->abort();
    _childSearch.reset();
    _childAbort = std::make_unique<abort_callback_impl>();

    NSString *artistStr = [_artistField stringValue];
    NSString *albumStr  = [_albumField  stringValue];
    NSString *titleStr  = [_titleField  stringValue];

    std::string artist = artistStr ? std::string([artistStr UTF8String]) : std::string();
    std::string album  = albumStr  ? std::string([albumStr  UTF8String]) : std::string();
    std::string title  = titleStr  ? std::string([titleStr  UTF8String]) : std::string();

    if (!core_api::are_services_available()) {
        [_statusLabel setStringValue:@"Services unavailable"];
        return;
    }

    try {
        _childSearch.emplace(LyricUpdate::Type::ManualSearch, _track, _trackInfo, *_childAbort);
    } catch (const std::exception& e) {
        LOG_WARN("Failed to create manual search handle: %s", e.what());
        [_statusLabel setStringValue:@"Search failed to start"];
        return;
    }

    io::search_for_all_lyrics(_childSearch.value(), artist, album, title);

    [_btnSearch setEnabled:NO];

    _pollTimer = [[NSTimer scheduledTimerWithTimeInterval:0.016
                                                   target:self
                                                 selector:@selector(onPollTimer:)
                                                 userInfo:nil
                                                  repeats:YES] retain];
}

- (void)stopPollTimer
{
    if (_pollTimer) {
        [_pollTimer invalidate];
        [_pollTimer release];
        _pollTimer = nil;
    }
}

- (void)onPollTimer:(NSTimer *)timer
{
    if (!_childSearch.has_value()) {
        [self stopPollTimer];
        [_btnSearch setEnabled:YES];
        return;
    }

    LyricSearchHandle& handle = _childSearch.value();

    // Drain any pending results
    while (handle.has_result()) {
        _allLyrics.push_back(handle.get_result());
        NSUInteger newRow = _allLyrics.size() - 1;
        [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:newRow]
                          withAnimation:NSTableViewAnimationEffectNone];

        // Auto-select the first result
        if (_allLyrics.size() == 1) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                    byExtendingSelection:NO];
        }
    }

    // Update status count
    NSUInteger count = _allLyrics.size();
    if (!handle.is_complete()) {
        if (count == 0) {
            [_statusLabel setStringValue:@"Searching..."];
        } else if (count == 1) {
            [_statusLabel setStringValue:@"1 result found..."];
        } else {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"%lu results found...",
                                          (unsigned long)count]];
        }
    }

    // Check for completion
    if (handle.is_complete() && !handle.has_result()) {
        [self stopPollTimer];
        [_btnSearch setEnabled:YES];
        _childSearch.reset();

        if (count == 0) {
            [_statusLabel setStringValue:@"No results found"];
        } else if (count == 1) {
            [_statusLabel setStringValue:@"1 result found"];
        } else {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"%lu results found",
                                          (unsigned long)count]];
        }
    }

    // Honour host shutdown
    if (core_api::are_services_available() && fb2k::mainAborter().is_aborting()) {
        if (_childAbort) _childAbort->abort();
    }
}

// ---------------------------------------------------------------------------
// Apply
// ---------------------------------------------------------------------------

- (void)applySelected
{
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || (NSUInteger)row >= _allLyrics.size()) return;
    if (!core_api::are_services_available()) return;

    LyricData copy = _allLyrics[(size_t)row];

    announce_lyric_update({
        std::move(copy),
        _track,
        _trackInfo,
        LyricUpdate::Type::ManualSearch,
    });
}

// ---------------------------------------------------------------------------
// NSTableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_allLyrics.size();
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= _allLyrics.size()) return @"";

    const LyricData& lyrics = _allLyrics[(size_t)row];

    NSString *colId = [tableColumn identifier];

    if ([colId isEqualToString:kColTitle]) {
        return [NSString stringWithUTF8String:lyrics.title.c_str()];
    } else if ([colId isEqualToString:kColArtist]) {
        return [NSString stringWithUTF8String:lyrics.artist.c_str()];
    } else if ([colId isEqualToString:kColAlbum]) {
        return [NSString stringWithUTF8String:lyrics.album.c_str()];
    } else if ([colId isEqualToString:kColSource]) {
        LyricSourceBase *src = LyricSourceBase::get(lyrics.source_id);
        if (src != nullptr) {
            std::tstring_view name = src->friendly_name();
            return [NSString stringWithUTF8String:std::string(name).c_str()];
        }
        return @"";
    } else if ([colId isEqualToString:kColTimestamped]) {
        return lyrics.IsTimestamped() ? @"Yes" : @"No";
    }
    return @"";
}

// ---------------------------------------------------------------------------
// NSTableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || (NSUInteger)row >= _allLyrics.size()) {
        [_previewText setString:@""];
        [_btnApply setEnabled:NO];
        return;
    }

    const LyricData& lyrics = _allLyrics[(size_t)row];

    std::tstring expanded = parsers::lrc::expand_text(lyrics, false);
    NSString *str = [NSString stringWithUTF8String:expanded.c_str()];
    [_previewText setString:(str ? str : @"")];
    [_previewText scrollRangeToVisible:NSMakeRange(0, 0)];
    [_btnApply setEnabled:YES];
}

@end

// ---------------------------------------------------------------------------
// SpawnManualSearchMac
// ---------------------------------------------------------------------------

void SpawnManualSearchMac(void)
{
    if (!core_api::are_services_available()) return;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ SpawnManualSearchMac(); });
        return;
    }

    if (g_searchPanel) {
        [[g_searchPanel window] makeKeyAndOrderFront:nil];
        return;
    }

    metadb_handle_ptr track;
    metadb_v2_rec_t trackInfo = {};

    auto pc = play_control::get();
    if (pc.is_valid()) {
        pc->get_now_playing(track);
    }
    if (track.is_valid()) {
        trackInfo = get_full_metadata(track);
    }

    g_searchPanel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:track
            trackInfo:trackInfo];
    [g_searchPanel showWindow:nil];
    // g_searchPanel is released in -windowWillClose:
}

void SpawnManualSearchMacForTrack(metadb_handle_ptr track, const metadb_v2_rec_t& info)
{
    if (!core_api::are_services_available()) return;

    if (![NSThread isMainThread]) {
        metadb_v2_rec_t infoCopy = info;
        dispatch_async(dispatch_get_main_queue(), ^{
            SpawnManualSearchMacForTrack(track, infoCopy);
        });
        return;
    }

    if (g_searchPanel) {
        [[g_searchPanel window] makeKeyAndOrderFront:nil];
        return;
    }

    g_searchPanel = [[OpenLyricsManualSearchPanel alloc]
        initWithTrack:track
            trackInfo:info];
    [g_searchPanel showWindow:nil];
    // g_searchPanel is released in -windowWillClose:
}
