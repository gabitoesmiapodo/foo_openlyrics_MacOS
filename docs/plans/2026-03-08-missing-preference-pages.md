# Missing Preference Pages Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port the 6 missing preference pages from the Windows UI to macOS NSViewController-based pages, reaching feature parity with the Windows OpenLyrics preferences tree.

**Architecture:** All preference pages live in a single file (`mac/OpenLyricsPreferences.mm`). Each page is an `NSViewController` subclass whose `loadView` builds the UI programmatically using shared helpers (`make_label`, `make_field`, `make_checkbox`, `make_popup`, `make_row`, `make_form`). A matching `preferences_page` subclass wraps the VC via `fb2k::wrapNSObject()` and registers it with `FB2K_SERVICE_FACTORY`. The `cfg_*` variables and their GUIDs are already declared in the same file -- they just need UI wired to them.

**Tech Stack:** Objective-C++ (`.mm`), AppKit (`NSStackView`, `NSPopUpButton`, `NSButton`, `NSColorWell`, `NSSlider`, `NSTextField`, `NSTableView`), foobar2000 SDK (`preferences_page`, `cfg_int`, `cfg_string`, `cfg_objList`)

---

## Reference: Existing Pattern

Every existing page in `mac/OpenLyricsPreferences.mm` follows this exact structure:

```objc
// 1. NSViewController subclass with @interface/@implementation
@interface OpenLyricsPrefs<Name>VC : NSViewController
@end
@implementation OpenLyricsPrefs<Name>VC
- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }
- (void)loadView {
    // Build controls, wire to cfg_* in action methods
    NSStackView* stack = make_form(@[...]);
    stack.frame = NSMakeRect(0, 0, W, H);
    self.view = stack;
}
// Action methods: read control value, write to cfg_*
@end

// 2. preferences_page subclass in anonymous namespace
class PrefsPage<Name> : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefs<Name>VC new]);
    }
    const char* get_name() override { return "Page Name"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_<NAME>; }
    GUID get_parent_guid() override { return <PARENT_GUID>; }
};
FB2K_SERVICE_FACTORY(PrefsPage<Name>)
```

Shared helpers already available:
- `make_label(NSString*)` -- read-only small label
- `make_field(NSString* placeholder)` -- editable text field
- `make_checkbox(NSString* title)` -- checkbox button
- `make_popup(NSArray<NSString*>*)` -- dropdown popup button
- `make_row(NSString* label, NSView* control)` -- horizontal label + control row (label width 160pt)
- `make_form(NSArray<NSView*>*)` -- vertical stack with 12pt insets, 8pt spacing

All `cfg_*` variables and GUIDs for the missing pages are already declared at the top of the file (lines 55-224). No new variables need to be created.

## Reference: Hierarchy and GUIDs

```
OpenLyrics (GUID_PREFERENCES_PAGE_ROOT, parent: guid_tools)      [exists]
  +-- Background (GUID_PREFS_PAGE_BACKGROUND, parent: ROOT)       [MISSING]
  +-- Display (GUID_PREFS_PAGE_DISPLAY, parent: ROOT)              [exists]
  +-- Editing (GUID_PREFS_PAGE_EDIT, parent: ROOT)                 [MISSING]
  +-- Saving (GUID_PREFS_PAGE_SAVING, parent: ROOT)                [exists]
  +-- Search sources (GUID_PREFERENCES_PAGE_SEARCH_SOURCES, parent: ROOT)  [MISSING]
  |     +-- Local files (GUID_PREFS_PAGE_SRC_LOCALFILES, parent: SEARCH_SOURCES)  [MISSING]
  |     +-- Metadata tags (GUID_PREFS_PAGE_SRC_METATAGS, parent: SEARCH_SOURCES)  [MISSING]
  |     +-- Musixmatch (GUID_PREFS_PAGE_SRC_MUSIXMATCH, parent: SEARCH_SOURCES)   [MISSING]
  +-- Searching (GUID_PREFS_PAGE_SEARCHING, parent: ROOT)          [exists]
  +-- Upload (GUID_PREFS_PAGE_UPLOAD, parent: ROOT)                [exists]
```

## Reference: cfg_* Variables (already declared, need UI only)

**Background:**
- `cfg_background_fill_type` (int, default `BackgroundFillType::Default`)
- `cfg_background_image_type` (int, default `BackgroundImageType::None`)
- `cfg_background_colour` (int/COLORREF, default `RGB(255,255,255)`)
- `cfg_background_gradient_tl` (int/COLORREF, default `RGB(11,145,255)`)
- `cfg_background_gradient_tr` (int/COLORREF, default `RGB(166,215,255)`)
- `cfg_background_gradient_bl` (int/COLORREF, default `RGB(100,185,255)`)
- `cfg_background_gradient_br` (int/COLORREF, default `RGB(255,255,255)`)
- `cfg_background_image_opacity` (int 0-100, default 16)
- `cfg_background_blur_radius` (int 0-32, default 6)
- `cfg_background_maintain_img_aspect_ratio` (int/bool, default 1)
- `cfg_background_custom_img_path` (string, default "")
- `cfg_background_externalwin_opaque` (int/bool, default 0)

**Editing:**
- `cfg_edit_auto_auto_edits` (`cfg_objList<int32_t>`, default `[ReplaceHtmlEscapedChars, RemoveRepeatedSpaces]`)

AutoEditType enum (from `src/preferences.h`):
```
ReplaceHtmlEscapedChars = 0
RemoveRepeatedSpaces = 1
RemoveSurroundingWhitespace = 2
RemoveRepeatedBlankLines = 3
RemoveAllBlankLines = 4
ResetCapitalisation = 5
FixMalformedTimestamps = 6
RemoveTimestamps = 7
```

**Search Sources:**
- `cfg_search_active_sources` (`cfg_objList<GUID>`, default `[localfiles, metadata_tags, qqmusic, netease]`)
- `cfg_search_active_sources_generation` (int, bumped on change)

**Local Files (shares save cfg vars):**
- `cfg_save_dir_class` (int, default `SaveDirectoryClass::ConfigDirectory`)
- `cfg_save_filename_format` (string, titleformat)
- `cfg_save_path_custom` (string, titleformat)

**Metadata Tags:**
- `cfg_search_tags` (string, semicolon-delimited, default "UNSYNCED LYRICS;LYRICS;SYNCEDLYRICS;UNSYNCEDLYRICS")
- `cfg_save_tag_untimed` (string, default "UNSYNCED LYRICS")
- `cfg_save_tag_timestamped` (string, default "UNSYNCED LYRICS")

**Musixmatch:**
- `cfg_search_musixmatch_token` (string, default "")

---

## Task 1: Background Page

**Files:**
- Modify: `mac/OpenLyricsPreferences.mm` (insert VC + page factory before the `PrefsPageDisplay` block)

**Step 1: Add the NSViewController**

Insert `OpenLyricsPrefsBackgroundVC` before the Display page section (before line 943). Use `NSColorWell` for color pickers, `NSSlider` for opacity/blur, `NSPopUpButton` for dropdowns.

```objc
// ---------------------------------------------------------------------------
// Background page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsBackgroundVC : NSViewController
@end

@implementation OpenLyricsPrefsBackgroundVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    // Fill type
    NSPopUpButton* fillPopup = make_popup(@[@"Default", @"Solid colour", @"Gradient"]);
    [fillPopup selectItemAtIndex:cfg_background_fill_type.get_value()];
    [fillPopup setTarget:self];
    [fillPopup setAction:@selector(onFillType:)];

    // Solid colour well
    NSColorWell* colourWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
    colourWell.color = [self nsColorFromRef:(uint32_t)cfg_background_colour.get_value()];
    colourWell.target = self;
    colourWell.action = @selector(onSolidColour:);

    // Gradient colour wells
    NSColorWell* gradTL = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
    gradTL.color = [self nsColorFromRef:(uint32_t)cfg_background_gradient_tl.get_value()];
    gradTL.tag = 0; gradTL.target = self; gradTL.action = @selector(onGradient:);

    NSColorWell* gradTR = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
    gradTR.color = [self nsColorFromRef:(uint32_t)cfg_background_gradient_tr.get_value()];
    gradTR.tag = 1; gradTR.target = self; gradTR.action = @selector(onGradient:);

    NSColorWell* gradBL = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
    gradBL.color = [self nsColorFromRef:(uint32_t)cfg_background_gradient_bl.get_value()];
    gradBL.tag = 2; gradBL.target = self; gradBL.action = @selector(onGradient:);

    NSColorWell* gradBR = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
    gradBR.color = [self nsColorFromRef:(uint32_t)cfg_background_gradient_br.get_value()];
    gradBR.tag = 3; gradBR.target = self; gradBR.action = @selector(onGradient:);

    // Image type
    NSPopUpButton* imgPopup = make_popup(@[@"None", @"Album art", @"Custom image"]);
    [imgPopup selectItemAtIndex:cfg_background_image_type.get_value()];
    [imgPopup setTarget:self];
    [imgPopup setAction:@selector(onImageType:)];

    // Opacity slider (0-100)
    NSSlider* opacitySlider = [NSSlider sliderWithValue:cfg_background_image_opacity.get_value()
                                               minValue:0 maxValue:100
                                                 target:self action:@selector(onOpacity:)];

    // Blur slider (0-32)
    NSSlider* blurSlider = [NSSlider sliderWithValue:cfg_background_blur_radius.get_value()
                                            minValue:0 maxValue:32
                                              target:self action:@selector(onBlur:)];

    // Maintain aspect ratio
    NSButton* aspectCheck = make_checkbox(@"Maintain image aspect ratio");
    aspectCheck.state = cfg_background_maintain_img_aspect_ratio.get_value()
                            ? NSControlStateValueOn : NSControlStateValueOff;
    [aspectCheck setTarget:self];
    [aspectCheck setAction:@selector(onAspectRatio:)];

    // Custom image path + browse
    NSTextField* imgPathField = make_field(@"path to image");
    imgPathField.stringValue = [NSString stringWithUTF8String:
        cfg_background_custom_img_path.get().c_str()];
    imgPathField.target = self;
    imgPathField.action = @selector(onCustomPath:);

    NSButton* browseBtn = [NSButton buttonWithTitle:@"Browse..."
                                             target:self action:@selector(onBrowseImage:)];

    NSStackView* pathRow = [NSStackView stackViewWithViews:@[imgPathField, browseBtn]];
    pathRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    pathRow.spacing = 4;

    // External window opaque
    NSButton* opaqueCheck = make_checkbox(@"Opaque in external window");
    opaqueCheck.state = cfg_background_externalwin_opaque.get_value()
                            ? NSControlStateValueOn : NSControlStateValueOff;
    [opaqueCheck setTarget:self];
    [opaqueCheck setAction:@selector(onExtOpaque:)];

    NSStackView* stack = make_form(@[
        make_row(@"Fill type:", fillPopup),
        make_row(@"Colour:", colourWell),
        make_row(@"Gradient TL:", gradTL),
        make_row(@"Gradient TR:", gradTR),
        make_row(@"Gradient BL:", gradBL),
        make_row(@"Gradient BR:", gradBR),
        make_row(@"Image type:", imgPopup),
        make_row(@"Image opacity:", opacitySlider),
        make_row(@"Blur radius:", blurSlider),
        aspectCheck,
        make_row(@"Custom image:", pathRow),
        opaqueCheck,
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 420);
    self.view = stack;
}

// --- Color conversion helpers ---

- (NSColor*)nsColorFromRef:(uint32_t)c
{
    return [NSColor colorWithRed:(c & 0xFF) / 255.0
                           green:((c >> 8) & 0xFF) / 255.0
                            blue:((c >> 16) & 0xFF) / 255.0
                           alpha:1.0];
}

- (uint32_t)colorRefFromNSColor:(NSColor*)color
{
    NSColor* rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) rgb = color;
    uint8_t r = (uint8_t)(rgb.redComponent * 255);
    uint8_t g = (uint8_t)(rgb.greenComponent * 255);
    uint8_t b = (uint8_t)(rgb.blueComponent * 255);
    return rgba_to_colorref(r, g, b);
}

// --- Actions ---

- (void)onFillType:(NSPopUpButton*)sender
{
    cfg_background_fill_type = (int)sender.indexOfSelectedItem;
    repaint_all_lyric_panels();
}

- (void)onSolidColour:(NSColorWell*)sender
{
    cfg_background_colour = (int)[self colorRefFromNSColor:sender.color];
    repaint_all_lyric_panels();
}

- (void)onGradient:(NSColorWell*)sender
{
    uint32_t c = [self colorRefFromNSColor:sender.color];
    switch (sender.tag) {
        case 0: cfg_background_gradient_tl = (int)c; break;
        case 1: cfg_background_gradient_tr = (int)c; break;
        case 2: cfg_background_gradient_bl = (int)c; break;
        case 3: cfg_background_gradient_br = (int)c; break;
    }
    repaint_all_lyric_panels();
}

- (void)onImageType:(NSPopUpButton*)sender
{
    cfg_background_image_type = (int)sender.indexOfSelectedItem;
    repaint_all_lyric_panels();
}

- (void)onOpacity:(NSSlider*)sender
{
    cfg_background_image_opacity = (int)sender.intValue;
    repaint_all_lyric_panels();
}

- (void)onBlur:(NSSlider*)sender
{
    cfg_background_blur_radius = (int)sender.intValue;
    repaint_all_lyric_panels();
}

- (void)onAspectRatio:(NSButton*)sender
{
    cfg_background_maintain_img_aspect_ratio = (sender.state == NSControlStateValueOn) ? 1 : 0;
    repaint_all_lyric_panels();
}

- (void)onCustomPath:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_background_custom_img_path.set(s ? s : "");
    repaint_all_lyric_panels();
}

- (void)onBrowseImage:(NSButton*)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[
        [UTType typeWithIdentifier:@"public.image"]
    ];
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        cfg_background_custom_img_path.set(panel.URL.path.UTF8String);
        repaint_all_lyric_panels();
    }
}

- (void)onExtOpaque:(NSButton*)sender
{
    cfg_background_externalwin_opaque = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

@end
```

Note: `#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>` may need to be added near the top of the file for `UTType`.

**Step 2: Add the preferences_page factory**

Insert inside the anonymous `namespace {}` block (before `PrefsPageDisplay`):

```cpp
class PrefsPageBackground : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefsBackgroundVC new]);
    }
    const char* get_name() override { return "Background"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_BACKGROUND; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageBackground)
```

**Step 3: Build and verify**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -20
```

Expected: tests pass, Background page appears in Preferences tree under OpenLyrics.

**Step 4: Commit**

```
git add mac/OpenLyricsPreferences.mm
git commit -m "Add Background preference page for macOS"
```

---

## Task 2: Editing Page

**Files:**
- Modify: `mac/OpenLyricsPreferences.mm`

**Step 1: Add the NSViewController**

Insert `OpenLyricsPrefsEditVC` after the Background page. The Editing page has a single control: a checklist of auto-edit options. Use a vertical stack of checkboxes (one per `AutoEditType` value).

```objc
// ---------------------------------------------------------------------------
// Editing page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsEditVC : NSViewController
@end

@implementation OpenLyricsPrefsEditVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    struct EditOption {
        AutoEditType type;
        NSString* label;
    };
    const EditOption options[] = {
        { AutoEditType::ReplaceHtmlEscapedChars,    @"Replace &-named HTML characters" },
        { AutoEditType::RemoveRepeatedSpaces,       @"Remove repeated spaces" },
        { AutoEditType::RemoveSurroundingWhitespace,@"Remove surrounding whitespace from each line" },
        { AutoEditType::RemoveRepeatedBlankLines,   @"Remove repeated blank lines" },
        { AutoEditType::RemoveAllBlankLines,        @"Remove all blank lines" },
        { AutoEditType::ResetCapitalisation,        @"Reset capitalisation" },
        { AutoEditType::FixMalformedTimestamps,     @"Fix malformed timestamps" },
        { AutoEditType::RemoveTimestamps,           @"Remove timestamps" },
    };

    // Build a set of currently-enabled types for fast lookup
    std::set<int> enabled;
    for (size_t i = 0; i < cfg_edit_auto_auto_edits.get_size(); i++)
        enabled.insert(cfg_edit_auto_auto_edits[i]);

    NSMutableArray* rows = [NSMutableArray array];
    [rows addObject:make_label(@"Automatic edits applied when lyrics are retrieved:")];

    for (const auto& opt : options) {
        NSButton* cb = make_checkbox(opt.label);
        cb.tag = static_cast<int>(opt.type);
        cb.state = enabled.count(cb.tag) ? NSControlStateValueOn : NSControlStateValueOff;
        [cb setTarget:self];
        [cb setAction:@selector(onToggleEdit:)];
        [rows addObject:cb];
    }

    NSStackView* stack = make_form(rows);
    stack.frame = NSMakeRect(0, 0, 540, 320);
    self.view = stack;
}

- (void)onToggleEdit:(NSButton*)sender
{
    // Rebuild the entire list from the current checkbox states
    // Walk up to find the parent form stack
    NSStackView* form = (NSStackView*)self.view;
    std::vector<int32_t> newList;
    for (NSView* v in form.arrangedSubviews) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* cb = (NSButton*)v;
            if (cb.state == NSControlStateValueOn)
                newList.push_back((int32_t)cb.tag);
        }
    }
    cfg_edit_auto_auto_edits.set_size(newList.size());
    for (size_t i = 0; i < newList.size(); i++)
        cfg_edit_auto_auto_edits[i] = newList[i];
}

@end
```

**Step 2: Add the preferences_page factory**

```cpp
class PrefsPageEdit : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefsEditVC new]);
    }
    const char* get_name() override { return "Editing"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_EDIT; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageEdit)
```

**Step 3: Build and verify**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -20
```

**Step 4: Commit**

```
git add mac/OpenLyricsPreferences.mm
git commit -m "Add Editing preference page for macOS"
```

---

## Task 3: Search Sources Page

**Files:**
- Modify: `mac/OpenLyricsPreferences.mm`

The Search Sources page has the most complex UI: two list boxes (active / inactive) with move-up/down/activate/deactivate buttons. Use `NSTableView` for the source lists.

**Step 1: Add the NSViewController**

```objc
// ---------------------------------------------------------------------------
// Search Sources page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsSearchSourcesVC : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
{
    std::vector<GUID> _activeSources;
    std::vector<GUID> _inactiveSources;
}
@property (nonatomic, strong) NSTableView* activeTable;
@property (nonatomic, strong) NSTableView* inactiveTable;
@end

@implementation OpenLyricsPrefsSearchSourcesVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    [self rebuildSourceLists];

    // Active sources table
    _activeTable = [self makeSourceTable];
    _activeTable.tag = 0;
    NSScrollView* activeScroll = [self wrapInScrollView:_activeTable height:160];

    // Inactive sources table
    _inactiveTable = [self makeSourceTable];
    _inactiveTable.tag = 1;
    NSScrollView* inactiveScroll = [self wrapInScrollView:_inactiveTable height:120];

    // Buttons
    NSButton* upBtn    = [NSButton buttonWithTitle:@"Move Up"    target:self action:@selector(onMoveUp:)];
    NSButton* downBtn  = [NSButton buttonWithTitle:@"Move Down"  target:self action:@selector(onMoveDown:)];
    NSButton* deactBtn = [NSButton buttonWithTitle:@"Deactivate" target:self action:@selector(onDeactivate:)];
    NSButton* actBtn   = [NSButton buttonWithTitle:@"Activate"   target:self action:@selector(onActivate:)];

    NSStackView* btns = [NSStackView stackViewWithViews:@[upBtn, downBtn, deactBtn, actBtn]];
    btns.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    btns.spacing = 4;

    NSStackView* stack = make_form(@[
        make_label(@"Active sources (searched in order):"),
        activeScroll,
        btns,
        make_label(@"Inactive sources:"),
        inactiveScroll,
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 400);
    self.view = stack;
}

- (void)rebuildSourceLists
{
    // Active: read from cfg
    _activeSources.clear();
    for (size_t i = 0; i < cfg_search_active_sources.get_size(); i++)
        _activeSources.push_back(cfg_search_active_sources[i]);

    // Inactive: all known sources minus active
    _inactiveSources.clear();
    std::set<GUID> activeSet(_activeSources.begin(), _activeSources.end());
    for (const auto& src : LyricSourceBase::get_all()) {
        if (activeSet.find(src->id()) == activeSet.end())
            _inactiveSources.push_back(src->id());
    }
}

- (void)saveActiveSources
{
    cfg_search_active_sources.set_size(_activeSources.size());
    for (size_t i = 0; i < _activeSources.size(); i++)
        cfg_search_active_sources[i] = _activeSources[i];
    cfg_search_active_sources_generation = cfg_search_active_sources_generation.get_value() + 1;
}

- (NSString*)nameForSource:(GUID)guid
{
    LyricSourceBase* src = LyricSourceBase::get(guid);
    if (src) return [NSString stringWithUTF8String:from_tstring(src->friendly_name()).c_str()];
    return @"(unknown)";
}

- (NSTableView*)makeSourceTable
{
    NSTableView* tv = [[NSTableView alloc] init];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.title = @"Source";
    col.width = 440;
    [tv addTableColumn:col];
    tv.headerView = nil;
    tv.dataSource = self;
    tv.delegate = self;
    return tv;
}

- (NSScrollView*)wrapInScrollView:(NSTableView*)tv height:(CGFloat)h
{
    NSScrollView* sv = [[NSScrollView alloc] init];
    sv.documentView = tv;
    sv.hasVerticalScroller = YES;
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [sv.heightAnchor constraintEqualToConstant:h].active = YES;
    return sv;
}

// --- NSTableViewDataSource ---

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv
{
    return (tv.tag == 0) ? (NSInteger)_activeSources.size()
                         : (NSInteger)_inactiveSources.size();
}

- (NSView*)tableView:(NSTableView*)tv viewForTableColumn:(NSTableColumn*)col row:(NSInteger)row
{
    NSTextField* cell = [NSTextField labelWithString:
        (tv.tag == 0) ? [self nameForSource:_activeSources[row]]
                      : [self nameForSource:_inactiveSources[row]]];
    cell.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return cell;
}

// --- Button actions ---

- (void)onMoveUp:(id)sender
{
    NSInteger row = _activeTable.selectedRow;
    if (row <= 0) return;
    std::swap(_activeSources[row], _activeSources[row - 1]);
    [self saveActiveSources];
    [_activeTable reloadData];
    [_activeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
}

- (void)onMoveDown:(id)sender
{
    NSInteger row = _activeTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_activeSources.size() - 1) return;
    std::swap(_activeSources[row], _activeSources[row + 1]);
    [self saveActiveSources];
    [_activeTable reloadData];
    [_activeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
}

- (void)onDeactivate:(id)sender
{
    NSInteger row = _activeTable.selectedRow;
    if (row < 0) return;
    GUID g = _activeSources[row];
    _activeSources.erase(_activeSources.begin() + row);
    _inactiveSources.push_back(g);
    [self saveActiveSources];
    [_activeTable reloadData];
    [_inactiveTable reloadData];
}

- (void)onActivate:(id)sender
{
    NSInteger row = _inactiveTable.selectedRow;
    if (row < 0) return;
    GUID g = _inactiveSources[row];
    _inactiveSources.erase(_inactiveSources.begin() + row);
    _activeSources.push_back(g);
    [self saveActiveSources];
    [_activeTable reloadData];
    [_inactiveTable reloadData];
}

@end
```

**Step 2: Add the preferences_page factory**

```cpp
class PrefsPageSearchSources : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefsSearchSourcesVC new]);
    }
    const char* get_name() override { return "Search sources"; }
    GUID get_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageSearchSources)
```

**Step 3: Build and verify**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -20
```

**Step 4: Commit**

```
git add mac/OpenLyricsPreferences.mm
git commit -m "Add Search Sources preference page for macOS"
```

---

## Task 4: Local Files Sub-page

**Files:**
- Modify: `mac/OpenLyricsPreferences.mm`

Simple form page. Shares `cfg_save_dir_class`, `cfg_save_filename_format`, `cfg_save_path_custom` with the Saving page (the Windows version also shares these).

**Step 1: Add VC + factory**

```objc
// ---------------------------------------------------------------------------
// Local Files sub-page (under Search Sources)
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsLocalFilesVC : NSViewController
@end

@implementation OpenLyricsPrefsLocalFilesVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    // Save directory class
    NSPopUpButton* dirPopup = make_popup(@[
        @"foobar2000 configuration directory",
        @"Same directory as the track",
        @"Custom directory",
    ]);
    [dirPopup selectItemAtIndex:cfg_save_dir_class.get_value()];
    [dirPopup setTarget:self];
    [dirPopup setAction:@selector(onDirClass:)];

    // Filename format
    NSTextField* fmtField = make_field(@"titleformat filename");
    fmtField.stringValue = [NSString stringWithUTF8String:cfg_save_filename_format.get().c_str()];
    fmtField.target = self;
    fmtField.action = @selector(onFilenameFormat:);

    // Custom path
    NSTextField* pathField = make_field(@"titleformat path");
    pathField.stringValue = [NSString stringWithUTF8String:cfg_save_path_custom.get().c_str()];
    pathField.target = self;
    pathField.action = @selector(onCustomPath:);

    NSStackView* stack = make_form(@[
        make_row(@"Search directory:", dirPopup),
        make_row(@"Filename format:", fmtField),
        make_row(@"Custom directory:", pathField),
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 160);
    self.view = stack;
}

- (void)onDirClass:(NSPopUpButton*)sender
{
    cfg_save_dir_class = (int)sender.indexOfSelectedItem;
}

- (void)onFilenameFormat:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_save_filename_format.set(s ? s : "");
}

- (void)onCustomPath:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_save_path_custom.set(s ? s : "");
}

@end
```

Factory:

```cpp
class PrefsPageLocalFiles : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefsLocalFilesVC new]);
    }
    const char* get_name() override { return "Local files"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SRC_LOCALFILES; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
};
FB2K_SERVICE_FACTORY(PrefsPageLocalFiles)
```

**Step 2: Build and verify**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -20
```

**Step 3: Commit**

```
git add mac/OpenLyricsPreferences.mm
git commit -m "Add Local Files preference sub-page for macOS"
```

---

## Task 5: Metadata Tags Sub-page

**Files:**
- Modify: `mac/OpenLyricsPreferences.mm`

**Step 1: Add VC + factory**

```objc
// ---------------------------------------------------------------------------
// Metadata Tags sub-page (under Search Sources)
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsMetaTagsVC : NSViewController
@end

@implementation OpenLyricsPrefsMetaTagsVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    // Search tags
    NSTextField* tagsField = make_field(@"UNSYNCED LYRICS;LYRICS;...");
    tagsField.stringValue = [NSString stringWithUTF8String:cfg_search_tags.get().c_str()];
    tagsField.target = self;
    tagsField.action = @selector(onSearchTags:);

    // Save tag for untimed
    NSTextField* untimedField = make_field(@"tag name");
    untimedField.stringValue = [NSString stringWithUTF8String:cfg_save_tag_untimed.get().c_str()];
    untimedField.target = self;
    untimedField.action = @selector(onUntimedTag:);

    // Save tag for timestamped
    NSTextField* timedField = make_field(@"tag name");
    timedField.stringValue = [NSString stringWithUTF8String:cfg_save_tag_timestamped.get().c_str()];
    timedField.target = self;
    timedField.action = @selector(onTimedTag:);

    NSTextField* note = [NSTextField wrappingLabelWithString:
        @"Search tags: semicolon-separated list of metadata fields to search for lyrics.\n"
        @"Save tags: which metadata field to write lyrics to when saving to tag.\n"
        @"\"UNSYNCED LYRICS\" is a special value that writes to the ID3 USLT frame."];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView* stack = make_form(@[
        make_row(@"Search tags:", tagsField),
        make_row(@"Save tag (unsynced):", untimedField),
        make_row(@"Save tag (synced):", timedField),
        note,
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 200);
    self.view = stack;
}

- (void)onSearchTags:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_search_tags.set(s ? s : "");
}

- (void)onUntimedTag:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_save_tag_untimed.set(s ? s : "");
}

- (void)onTimedTag:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_save_tag_timestamped.set(s ? s : "");
}

@end
```

Factory:

```cpp
class PrefsPageMetaTags : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefsMetaTagsVC new]);
    }
    const char* get_name() override { return "Metadata tags"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SRC_METATAGS; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
};
FB2K_SERVICE_FACTORY(PrefsPageMetaTags)
```

**Step 2: Build and verify**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -20
```

**Step 3: Commit**

```
git add mac/OpenLyricsPreferences.mm
git commit -m "Add Metadata Tags preference sub-page for macOS"
```

---

## Task 6: Musixmatch Sub-page

**Files:**
- Modify: `mac/OpenLyricsPreferences.mm`

Note: The Musixmatch token field already exists on the Searching page (line 774). The dedicated sub-page adds a show/hide toggle for the token. After implementing this page, remove the duplicate Musixmatch token field from `OpenLyricsPrefsSearchVC` to avoid confusion.

**Step 1: Add VC + factory**

```objc
// ---------------------------------------------------------------------------
// Musixmatch sub-page (under Search Sources)
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsMusixmatchVC : NSViewController
@property (nonatomic, weak) NSSecureTextField* secureField;
@property (nonatomic, weak) NSTextField* plainField;
@property (nonatomic, assign) BOOL tokenVisible;
@end

@implementation OpenLyricsPrefsMusixmatchVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; _tokenVisible = NO; return self; }

- (void)loadView
{
    NSString* token = [NSString stringWithUTF8String:cfg_search_musixmatch_token.get().c_str()];

    // Secure (masked) field
    NSSecureTextField* secField = [[NSSecureTextField alloc] init];
    secField.placeholderString = @"Musixmatch user token";
    secField.stringValue = token;
    secField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    secField.target = self;
    secField.action = @selector(onToken:);
    _secureField = secField;

    // Plain (visible) field, initially hidden
    NSTextField* plainF = make_field(@"Musixmatch user token");
    plainF.stringValue = token;
    plainF.target = self;
    plainF.action = @selector(onToken:);
    plainF.hidden = YES;
    _plainField = plainF;

    NSStackView* fieldStack = [NSStackView stackViewWithViews:@[secField, plainF]];
    fieldStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    fieldStack.spacing = 0;

    // Show/Hide button
    NSButton* showBtn = [NSButton buttonWithTitle:@"Show token"
                                           target:self action:@selector(onToggleShow:)];

    NSTextField* note = [NSTextField wrappingLabelWithString:
        @"A Musixmatch user token is required to search Musixmatch for lyrics. "
        @"See the OpenLyrics wiki for instructions on how to obtain one."];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView* stack = make_form(@[
        make_row(@"Token:", fieldStack),
        showBtn,
        note,
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 180);
    self.view = stack;
}

- (void)onToken:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_search_musixmatch_token.set(s ? s : "");
    // Sync the other field
    NSString* val = sender.stringValue;
    if (sender == (NSTextField*)_secureField)
        _plainField.stringValue = val;
    else
        _secureField.stringValue = val;
}

- (void)onToggleShow:(NSButton*)sender
{
    _tokenVisible = !_tokenVisible;
    _secureField.hidden = _tokenVisible;
    _plainField.hidden = !_tokenVisible;
    sender.title = _tokenVisible ? @"Hide token" : @"Show token";
}

@end
```

Factory:

```cpp
class PrefsPageMusixmatch : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([OpenLyricsPrefsMusixmatchVC new]);
    }
    const char* get_name() override { return "Musixmatch"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SRC_MUSIXMATCH; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
};
FB2K_SERVICE_FACTORY(PrefsPageMusixmatch)
```

**Step 2: Remove duplicate Musixmatch token from Searching page**

In `OpenLyricsPrefsSearchVC`'s `loadView`, remove the Musixmatch field and its row from `make_form`:

Remove:
```objc
    // Musixmatch API key
    NSTextField* mmField = make_field(@"Musixmatch token (optional)");
    mmField.stringValue = [NSString stringWithUTF8String:cfg_search_musixmatch_token.get().c_str()];
    mmField.tag = 2;
    mmField.target = self;
    mmField.action = @selector(onMusixmatch:);
```

And remove `make_row(@"Musixmatch token:", mmField)` from the `make_form` call.
And remove the `onMusixmatch:` action method.

**Step 3: Rename "Upload" to "Uploading"**

In the `PrefsPageUpload` factory class, change:
```cpp
const char* get_name() override { return "Uploading"; }
```

This matches the Windows naming.

**Step 4: Build and verify**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -20
```

Expected: full preferences tree matches Windows:
```
OpenLyrics
  Background
  Display
  Editing
  Saving
  Search sources
    Local files
    Metadata tags
    Musixmatch
  Searching
  Uploading
```

**Step 5: Commit**

```
git add mac/OpenLyricsPreferences.mm
git commit -m "Add Musixmatch preference sub-page, remove duplicate token field, rename Upload to Uploading"
```

---

## Task 7: Final Verification

**Step 1: Full build from clean state**

```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build 2>&1 | tail -30
```

All tests must pass.

**Step 2: Manual verification checklist**

Open foobar2000 > Preferences > Tools > OpenLyrics and verify:

- [ ] All 11 pages appear in the correct tree hierarchy
- [ ] Background: fill type dropdown changes background; colour wells work; sliders for opacity/blur respond; browse button opens file picker
- [ ] Editing: checkboxes toggle auto-edit types; changes persist after restarting foobar2000
- [ ] Search sources: active/inactive lists populated; move up/down/activate/deactivate buttons work
- [ ] Local files: directory class dropdown and format fields persist values
- [ ] Metadata tags: search tags and save tag fields persist values
- [ ] Musixmatch: token field is masked by default; show/hide toggle works

**Step 3: Commit if any manual verification fixes were needed**
