// mac/OpenLyricsEditor.mm
// Lyric editor panel for the macOS foo_openlyrics port.
// Provides an NSPanel-based editor mirroring the upstream Windows LyricEditor dialog.

#import "stdafx.h"
#import "OpenLyricsEditor.h"
#import "OpenLyricsView.h"

#include "../src/lyric_io.h"
#include "../src/logging.h"
#include "../src/parsers.h"
#include "../src/ui_hooks.h"
#include "../src/lyric_metadata.h"

// ---------------------------------------------------------------------------
// Forward declaration: implemented in OpenLyricsView.mm
// ---------------------------------------------------------------------------

// Returns a copy of the LyricData currently displayed in any active panel.
// Returns an empty LyricData if no panels are active or have lyrics.
LyricData get_active_panel_lyrics(metadb_handle_ptr& out_track, metadb_v2_rec_t& out_info);

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------

static OpenLyricsEditorPanel* g_editorPanel = nil;

// ---------------------------------------------------------------------------
// OpenLyricsEditorPanel
// ---------------------------------------------------------------------------

@interface OpenLyricsEditorPanel () {
    LyricData      _lyrics;         // original lyrics at open time (for reset)
    LyricData      _workingLyrics;  // copy used by ParseEditorContents
    metadb_handle_ptr _track;
    metadb_v2_rec_t   _trackInfo;
    std::string    _inputText;      // LRC text at open time (for HasContentChanged)

    NSTextView    *_textView;
    NSScrollView  *_scrollView;
    NSButton      *_btnBack5;
    NSButton      *_btnPlay;
    NSButton      *_btnFwd5;
    NSButton      *_btnSync;
    NSButton      *_btnReset;
    NSButton      *_btnApplyOffset;
    NSButton      *_btnSyncOffset;
    NSTextField   *_timeLabel;
    NSButton      *_btnCancel;
    NSButton      *_btnApply;
    NSButton      *_btnOK;

    NSTimer       *_tickTimer;   // updates time label ~1 Hz
}

@property (nonatomic, readwrite) NSTextView *textView;

- (void)buildUI;
- (void)updateTimeLabel;
- (void)updatePlayButton;
- (bool)hasContentChanged;
- (void)applyLyricEdits;
- (LyricData)parseEditorContents;
- (void)setEditorContents:(const LyricData&)lyrics;

@end

@implementation OpenLyricsEditorPanel

@synthesize textView = _textView;

- (instancetype)initWithCoder:(NSCoder *)coder
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

- (instancetype)initWithLyrics:(const LyricData&)lyrics
                         track:(metadb_handle_ptr)track
                    trackInfo:(const metadb_v2_rec_t&)trackInfo
{
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 680, 520)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [panel setTitle:@"Lyric Editor"];
    [panel setFloatingPanel:NO];
    [panel center];

    self = [super initWithWindow:panel];
    [panel release];

    if (self) {
        _lyrics      = lyrics;
        _workingLyrics = lyrics;
        _track       = track;
        _trackInfo   = trackInfo;

        // Pre-compute the initial text for change detection
        std::tstring expanded = parsers::lrc::expand_text(lyrics, false);
        _inputText = std::string(expanded.begin(), expanded.end());

        [self buildUI];
        [self setEditorContents:lyrics];

        self.window.delegate = self;

        // Start tick timer for time label updates
        _tickTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(onTick:)
                                                     userInfo:nil
                                                      repeats:YES] retain];
        [self updateTimeLabel];
        [self updatePlayButton];
        [self updatePlaybackControlsEnabled];
    }
    return self;
}

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------

- (void)buildUI
{
    NSView *content = self.window.contentView;

    // ---- Toolbar row (top) -------------------------------------------------
    CGFloat tbY = 480;
    CGFloat btnH = 26;
    CGFloat btnW = 80;
    CGFloat gap  = 6;
    CGFloat x    = 10;

    _btnBack5 = [self makeButton:@"<< 5s" action:@selector(onBack5:) frame:NSMakeRect(x, tbY, btnW, btnH)];
    [content addSubview:_btnBack5];
    x += btnW + gap;

    _btnPlay = [self makeButton:@"Play" action:@selector(onPlayPause:) frame:NSMakeRect(x, tbY, btnW, btnH)];
    [content addSubview:_btnPlay];
    x += btnW + gap;

    _btnFwd5 = [self makeButton:@"5s >>" action:@selector(onFwd5:) frame:NSMakeRect(x, tbY, btnW, btnH)];
    [content addSubview:_btnFwd5];
    x += btnW + gap + 10; // extra gap

    _btnSync = [self makeButton:@"Insert Timestamp" action:@selector(onInsertTimestamp:) frame:NSMakeRect(x, tbY, 130, btnH)];
    [content addSubview:_btnSync];
    x += 130 + gap;

    _btnReset = [self makeButton:@"Reset" action:@selector(onReset:) frame:NSMakeRect(x, tbY, btnW, btnH)];
    [content addSubview:_btnReset];
    x += btnW + gap;

    _btnApplyOffset = [self makeButton:@"Apply Offset" action:@selector(onApplyOffset:) frame:NSMakeRect(x, tbY, 100, btnH)];
    [_btnApplyOffset setToolTip:@"Remove the existing 'offset' tag and apply the offset directly to every timestamp in these lyrics"];
    [content addSubview:_btnApplyOffset];
    x += 100 + gap;

    _btnSyncOffset = [self makeButton:@"Sync Offset" action:@selector(onSyncOffset:) frame:NSMakeRect(x, tbY, 100, btnH)];
    [_btnSyncOffset setToolTip:@"Add an 'offset' tag that synchronises all lines instead of modifying the selected line's timestamp"];
    [content addSubview:_btnSyncOffset];

    // ---- Time label --------------------------------------------------------
    _timeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, tbY - 24, 400, 18)];
    [_timeLabel setBezeled:NO];
    [_timeLabel setDrawsBackground:NO];
    [_timeLabel setEditable:NO];
    [_timeLabel setSelectable:NO];
    [_timeLabel setStringValue:@""];
    [_timeLabel setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:_timeLabel];
    [_timeLabel release];

    // ---- Text view (main editing area) ------------------------------------
    CGFloat tvTop    = tbY - 28;
    CGFloat bottomH  = 40; // space for Cancel/Apply/OK
    CGFloat tvHeight = tvTop - bottomH - 4;

    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, bottomH + 4, 660, tvHeight)];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:NO];
    [_scrollView setBorderType:NSBezelBorder];
    [_scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 660, tvHeight)];
    [_textView setMinSize:NSMakeSize(0, tvHeight)];
    [_textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [_textView setVerticallyResizable:YES];
    [_textView setHorizontallyResizable:NO];
    [_textView setAutoresizingMask:NSViewWidthSizable];
    [_textView textContainer].widthTracksTextView = YES;
    [_textView setFont:[NSFont userFixedPitchFontOfSize:13]];
    [_textView setAllowsUndo:YES];
    [_textView setDelegate:(id<NSTextViewDelegate>)self];

    [_scrollView setDocumentView:_textView];
    [content addSubview:_scrollView];
    [_textView release];
    [_scrollView release];

    // ---- Bottom button row -------------------------------------------------
    CGFloat bY = 8;
    CGFloat bW = 80;

    _btnOK = [self makeButton:@"OK" action:@selector(onOK:) frame:NSMakeRect(660 - bW - 10, bY, bW, 26)];
    [content addSubview:_btnOK];

    _btnApply = [self makeButton:@"Apply" action:@selector(onApply:) frame:NSMakeRect(660 - bW*2 - gap - 10, bY, bW, 26)];
    [_btnApply setEnabled:NO];
    [content addSubview:_btnApply];

    _btnCancel = [self makeButton:@"Cancel" action:@selector(onCancel:) frame:NSMakeRect(660 - bW*3 - gap*2 - 10, bY, bW, 26)];
    [content addSubview:_btnCancel];
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

// ---------------------------------------------------------------------------
// Dealloc
// ---------------------------------------------------------------------------

- (void)dealloc
{
    [_tickTimer invalidate];
    [_tickTimer release];
    _tickTimer = nil;
    [super dealloc];
}

// ---------------------------------------------------------------------------
// NSWindowDelegate
// ---------------------------------------------------------------------------

- (void)windowWillClose:(NSNotification *)notification
{
    [_tickTimer invalidate];
    [_tickTimer release];
    _tickTimer = nil;

    if (g_editorPanel == self) {
        // Release the retain from SpawnLyricEditorMac's alloc.
        // Guard prevents double-release when the panel was created directly (e.g. in tests).
        g_editorPanel = nil;
        [self release];
    }
}

// ---------------------------------------------------------------------------
// Timer tick
// ---------------------------------------------------------------------------

- (void)onTick:(NSTimer *)timer
{
    [self updateTimeLabel];
    [self updatePlayButton];
    [self updatePlaybackControlsEnabled];
}

// ---------------------------------------------------------------------------
// Playback helpers
// ---------------------------------------------------------------------------

- (void)updateTimeLabel
{
    if (!core_api::are_services_available()) {
        [_timeLabel setStringValue:@"Services unavailable"];
        return;
    }

    auto pc = play_control::get();
    if (!pc.is_valid() || !pc->is_playing()) {
        [_timeLabel setStringValue:@"Not playing"];
        return;
    }

    metadb_handle_ptr nowPlaying;
    bool havePlaying = pc->get_now_playing(nowPlaying);

    bool editTrackPlaying = havePlaying && _track.is_valid() && (nowPlaying == _track);
    if (editTrackPlaying) {
        double pos = pc->playback_get_position();
        int total_sec = (int)pos;
        int mm = total_sec / 60;
        int ss = total_sec % 60;
        NSString *str = [NSString stringWithFormat:@"Playback time: %02d:%02d", mm, ss];
        [_timeLabel setStringValue:str];
    } else {
        [_timeLabel setStringValue:@"This track is not playing..."];
    }
}

- (void)updatePlayButton
{
    if (!core_api::are_services_available()) return;
    auto pc = play_control::get();
    if (!pc.is_valid()) return;
    bool playing = pc->is_playing() && !pc->is_paused();
    [_btnPlay setTitle:(playing ? @"Pause" : @"Play")];
}

- (void)updatePlaybackControlsEnabled
{
    if (!core_api::are_services_available()) {
        [_btnBack5  setEnabled:NO];
        [_btnPlay   setEnabled:NO];
        [_btnFwd5   setEnabled:NO];
        [_btnSync   setEnabled:NO];
        return;
    }

    auto pc = play_control::get();
    bool playing = pc.is_valid() && pc->is_playing();

    bool editTrackPlaying = NO;
    if (playing && _track.is_valid()) {
        metadb_handle_ptr nowPlaying;
        if (pc->get_now_playing(nowPlaying)) {
            editTrackPlaying = (nowPlaying == _track);
        }
    }

    [_btnBack5 setEnabled:(editTrackPlaying ? YES : NO)];
    [_btnPlay  setEnabled:(playing         ? YES : NO)];
    [_btnFwd5  setEnabled:(editTrackPlaying ? YES : NO)];
    [_btnSync  setEnabled:(editTrackPlaying ? YES : NO)];
}

// ---------------------------------------------------------------------------
// Toolbar actions
// ---------------------------------------------------------------------------

- (void)onBack5:(id)sender
{
    if (!core_api::are_services_available()) return;
    auto pc = play_control::get();
    if (pc.is_valid()) pc->playback_seek_delta(-5.0);
}

- (void)onFwd5:(id)sender
{
    if (!core_api::are_services_available()) return;
    auto pc = play_control::get();
    if (pc.is_valid()) pc->playback_seek_delta(5.0);
}

- (void)onPlayPause:(id)sender
{
    if (!core_api::are_services_available()) return;
    auto pc = play_control::get();
    if (pc.is_valid()) pc->play_or_pause();
}

- (void)onInsertTimestamp:(id)sender
{
    if (!core_api::are_services_available()) return;
    auto pc = play_control::get();
    if (!pc.is_valid()) return;

    LyricData parsed = [self parseEditorContents];
    double pos = pc->playback_get_position() + parsed.timestamp_offset;
    std::string ts_str = parsers::lrc::print_timestamp(pos);
    NSString *ts = [NSString stringWithUTF8String:ts_str.c_str()];

    // Determine the current line in the text view so we can replace any
    // existing timestamp at the start of that line (matching upstream behaviour).
    NSString *fullText = [_textView string];
    NSRange sel = [_textView selectedRange];
    if (sel.location == NSNotFound) sel.location = 0;

    // Find the start of the current line
    NSUInteger lineStart = 0;
    NSUInteger lineEnd   = 0;
    NSUInteger contentsEnd = 0;
    [fullText getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(sel.location, 0)];

    // Build replacement range: if the line starts with [mm:ss.xx], replace it
    NSRange replaceRange = NSMakeRange(lineStart, 0); // default: insert at line start
    if (lineStart < fullText.length && [fullText characterAtIndex:lineStart] == '[') {
        // Find the closing ']'
        NSRange searchRange = NSMakeRange(lineStart, MIN(32UL, contentsEnd - lineStart));
        NSRange closeBracket = [fullText rangeOfString:@"]" options:0 range:searchRange];
        if (closeBracket.location != NSNotFound) {
            NSString *candidate = [fullText substringWithRange:
                NSMakeRange(lineStart, closeBracket.location - lineStart + 1)];
            std::string cand_str = std::string([candidate UTF8String]);
            double dummy = 0.0;
            if (parsers::lrc::try_parse_timestamp(cand_str, dummy)) {
                replaceRange = NSMakeRange(lineStart, closeBracket.location - lineStart + 1);
            }
        }
    }

    [[_textView textStorage] replaceCharactersInRange:replaceRange withString:ts];

    // Advance selection to start of next line
    NSString *newText = [_textView string];
    NSRange newSel = NSMakeRange(replaceRange.location + ts.length, 0);
    // move to next line start
    NSUInteger nls = 0, nle = 0, nlce = 0;
    [newText getLineStart:&nls end:&nle contentsEnd:&nlce forRange:newSel];
    if (nle < newText.length) {
        [_textView setSelectedRange:NSMakeRange(nle, 0)];
        [_textView scrollRangeToVisible:NSMakeRange(nle, 0)];
    }

    [_btnApply setEnabled:YES];
}

- (void)onReset:(id)sender
{
    [self setEditorContents:_lyrics];
    [_btnApply setEnabled:NO];
}

- (void)onApplyOffset:(id)sender
{
    LyricData parsed = [self parseEditorContents];
    if (!parsed.IsTimestamped()) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Synchronisation Error"];
        [alert setInformativeText:@"Cannot apply offset tag to unsynchronised lyrics"];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        return;
    }
    if (parsed.timestamp_offset == 0.0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Synchronisation Error"];
        [alert setInformativeText:@"Cannot apply offset tag as there is no offset to apply"];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        return;
    }

    for (size_t i = 0; i < parsed.lines.size(); i++) {
        parsed.lines[i].timestamp = parsed.LineTimestamp((int)i);
    }
    parsers::lrc::remove_offset_tag(parsed);
    [self setEditorContents:parsed];
    [_btnApply setEnabled:YES];
}

- (void)onSyncOffset:(id)sender
{
    LyricData parsed = [self parseEditorContents];

    NSString *fullText = [_textView string];
    NSRange sel = [_textView selectedRange];
    if (sel.location == NSNotFound) sel.location = 0;

    NSUInteger lineStart = 0, lineEnd = 0, contentsEnd = 0;
    [fullText getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(sel.location, 0)];

    NSString *lineText = [fullText substringWithRange:NSMakeRange(lineStart, contentsEnd - lineStart)];
    std::string lineStr = std::string([lineText UTF8String]);

    double currLineTimestamp = parsers::lrc::get_line_first_timestamp(lineStr);
    if (currLineTimestamp == DBL_MAX) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Synchronisation Error"];
        [alert setInformativeText:@"The currently-selected line does not have a timestamp"];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        return;
    }

    if (!core_api::are_services_available()) return;
    auto pc = play_control::get();
    if (!pc.is_valid()) return;
    double currentTime = pc->playback_get_position();
    double requiredOffsetSec = currLineTimestamp - currentTime;
    parsers::lrc::set_offset_tag(parsed, requiredOffsetSec);

    [self setEditorContents:parsed];
    [_btnApply setEnabled:YES];
}

// ---------------------------------------------------------------------------
// Bottom buttons
// ---------------------------------------------------------------------------

- (void)onCancel:(id)sender
{
    [self.window close];
}

- (void)onApply:(id)sender
{
    [self applyLyricEdits];
}

- (void)onOK:(id)sender
{
    if ([self hasContentChanged]) {
        [self applyLyricEdits];
    }
    [self.window close];
}

// ---------------------------------------------------------------------------
// NSTextViewDelegate — track changes to enable Apply button
// ---------------------------------------------------------------------------

- (void)textDidChange:(NSNotification *)notification
{
    bool changed = [self hasContentChanged];
    bool empty = ([_textView string].length == 0);
    [_btnApply setEnabled:(changed && !empty ? YES : NO)];
}

// ---------------------------------------------------------------------------
// Lyric helpers
// ---------------------------------------------------------------------------

- (void)setEditorContents:(const LyricData&)lyrics
{
    std::tstring expanded = parsers::lrc::expand_text(lyrics, false);
    NSString *str = [NSString stringWithUTF8String:expanded.c_str()];
    [_textView setString:(str ? str : @"")];
    [_textView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (bool)hasContentChanged
{
    NSString *current = [_textView string];
    if (!current) return (_inputText.size() > 0);
    const char *utf8 = [current UTF8String];
    if (!utf8) return (_inputText.size() > 0);
    return (std::string(utf8) != _inputText);
}

- (LyricData)parseEditorContents
{
    NSString *str = [_textView string];
    std::string text = str ? std::string([str UTF8String]) : std::string();
    return parsers::lrc::parse(_lyrics, text);
}

- (void)applyLyricEdits
{
    if (!core_api::are_services_available()) return;

    LOG_INFO("Saving lyrics from editor...");
    LyricData data = [self parseEditorContents];
    if (data.IsEmpty()) return;

    announce_lyric_update({
        std::move(data),
        _track,
        _trackInfo,
        LyricUpdate::Type::Edit,
    });

    // Update baseline so HasContentChanged tracks from the new saved state
    NSString *current = [_textView string];
    if (current) _inputText = std::string([current UTF8String]);

    [_btnApply setEnabled:NO];
}

@end

// ---------------------------------------------------------------------------
// get_active_panel_lyrics — defined here so OpenLyricsView.mm can forward-declare it
// ---------------------------------------------------------------------------
// The implementation lives in OpenLyricsView.mm. We only need to provide the
// declaration here; the real body is in that file. Since we cannot reach into
// OpenLyricsView's private ivars from here we use the public accessor.

// ---------------------------------------------------------------------------
// SpawnLyricEditorMac
// ---------------------------------------------------------------------------

void SpawnLyricEditorMac(void)
{
    // No-op in test context (no foobar2000 host process).
    if (!core_api::are_services_available()) return;

    // Must run on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ SpawnLyricEditorMac(); });
        return;
    }

    if (g_editorPanel) {
        [[g_editorPanel window] makeKeyAndOrderFront:nil];
        return;
    }

    LyricData lyrics;
    metadb_handle_ptr track;
    metadb_v2_rec_t trackInfo = {};

    if (core_api::are_services_available()) {
        auto pc = play_control::get();
        if (pc.is_valid()) {
            pc->get_now_playing(track);
        }
    }

    // Retrieve lyrics from the active panel(s).
    // We call the function implemented in OpenLyricsView.mm.
    lyrics = get_active_panel_lyrics(track, trackInfo);

    g_editorPanel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:track
             trackInfo:trackInfo];
    [g_editorPanel showWindow:nil];
    // g_editorPanel is released in -windowWillClose:
}

void SpawnLyricEditorMacForTrack(const LyricData& lyrics, metadb_handle_ptr track,
                                  const metadb_v2_rec_t& trackInfo)
{
    if (!core_api::are_services_available()) return;

    if (![NSThread isMainThread]) {
        LyricData lyricsCopy   = lyrics;
        metadb_v2_rec_t infoCopy = trackInfo;
        dispatch_async(dispatch_get_main_queue(), ^{
            SpawnLyricEditorMacForTrack(lyricsCopy, track, infoCopy);
        });
        return;
    }

    if (g_editorPanel) {
        [[g_editorPanel window] makeKeyAndOrderFront:nil];
        return;
    }

    g_editorPanel = [[OpenLyricsEditorPanel alloc]
        initWithLyrics:lyrics
                 track:track
             trackInfo:trackInfo];
    [g_editorPanel showWindow:nil];
    // g_editorPanel is released in -windowWillClose:
}
