// mac/OpenLyricsPreferences.mm
// Persistent preferences for foo_openlyrics on macOS.
// Uses foobar2000 SDK cfg_* variables (same GUIDs as Windows for config compatibility).
// Registers NSViewController-based preference pages with the foobar2000 preferences dialog.
#include "stdafx.h"

#include "../src/img_processing.h"
#include "../src/logging.h"
#include "../src/preferences.h"
#include "../src/sources/lyric_source.h"
#include "../src/tag_util.h"
#include "../src/ui_hooks.h"

// macOS SDK uses FOOBAR2000_TARGET_VERSION=81 (cfg_var_modern).
// cfg_objList is in helpers, not the SDK core.
#include <helpers/cfg_objList.h>

// ---------------------------------------------------------------------------
// Helper: inline color conversion (avoids dependency on img_processing.cpp)
// ---------------------------------------------------------------------------

static inline RGBAColour colorref_to_rgba(uint32_t c)
{
    return { uint8_t(c & 0xFF), uint8_t((c >> 8) & 0xFF), uint8_t((c >> 16) & 0xFF), 255 };
}

static inline uint32_t rgba_to_colorref(uint8_t r, uint8_t g, uint8_t b)
{
    return uint32_t(r) | (uint32_t(g) << 8) | (uint32_t(b) << 16);
}

// Platform-compatible RGB macro (COLORREF: R | G<<8 | B<<16)
#ifndef RGB
#define RGB(r, g, b) (uint32_t(r) | (uint32_t(g) << 8) | (uint32_t(b) << 16))
#endif

// ===========================================================================
// Preference page GUIDs (match Windows for cross-platform config compat)
// ===========================================================================

// clang-format off
extern const GUID GUID_PREFERENCES_PAGE_ROOT         = { 0x29e96cfa, 0xab67, 0x4793, { 0xa1, 0xc3, 0xef, 0xc3, 0x0a, 0xbc, 0x8b, 0x74 } };
extern const GUID GUID_PREFERENCES_PAGE_SEARCH_SOURCES = { 0x73e2261d, 0x4a71, 0x427a, { 0x92, 0x57, 0xec, 0xaa, 0x17, 0xb9, 0xa8, 0xc8 } };
static const GUID GUID_PREFS_PAGE_SEARCHING = { 0xf835ba65, 0x9a56, 0x4c0f, { 0xb1, 0x23, 0x08, 0x53, 0x67, 0x97, 0x4e, 0xed } };
static const GUID GUID_PREFS_PAGE_SAVING    = { 0x0d5a7534, 0x9f59, 0x444c, { 0x8d, 0x6f, 0xec, 0xf3, 0x7f, 0x61, 0xfc, 0xf1 } };
static const GUID GUID_PREFS_PAGE_DISPLAY   = { 0xa31b1608, 0xe77f, 0x4fe5, { 0x80, 0x4b, 0xcf, 0x8c, 0xc8, 0x17, 0xd8, 0x69 } };
static const GUID GUID_PREFS_PAGE_BACKGROUND = { 0xd4c823dc, 0x0e71, 0x4c5c, { 0xad, 0x27, 0xcb, 0xf1, 0xd4, 0x78, 0x41, 0x4b } };
static const GUID GUID_PREFS_PAGE_EDIT      = { 0x6187e852, 0x199c, 0x4dc2, { 0x85, 0x21, 0x65, 0x39, 0x09, 0xc0, 0xeb, 0x3c } };
static const GUID GUID_PREFS_PAGE_UPLOAD    = { 0x8699d695, 0x1b56, 0x4898, { 0xaa, 0x57, 0xeb, 0xb3, 0x35, 0x7b, 0xd7, 0x09 } };
static const GUID GUID_PREFS_PAGE_SRC_LOCALFILES = { 0x9f2e83b6, 0xccc3, 0x4033, { 0xb5, 0x84, 0xf3, 0x84, 0x2d, 0xad, 0xfb, 0x40 } };
static const GUID GUID_PREFS_PAGE_SRC_METATAGS   = { 0x23c180eb, 0x1f8f, 0x4cf1, { 0x90, 0x2e, 0x31, 0x56, 0x2f, 0xa9, 0x4f, 0xf5 } };
static const GUID GUID_PREFS_PAGE_SRC_MUSIXMATCH  = { 0x5abc3564, 0xefb5, 0x4464, { 0xb0, 0x38, 0x28, 0xde, 0x08, 0x16, 0x0a, 0x76 } };

// ---------------------------------------------------------------------------
// cfg_* variable GUIDs (must match Windows exactly for config compatibility)
// ---------------------------------------------------------------------------

// Root / display
static const GUID GUID_CFG_DEBUG_LOGS_ENABLED             = { 0x57920cbe, 0x0a27, 0x4fad, { 0x92, 0xc0, 0x2b, 0x61, 0x3b, 0xf9, 0xd6, 0x13 } };

// Searching
static const GUID GUID_CFG_SEARCH_EXCLUDE_TRAILING_BRACKETS = { 0x2cbdf6c3, 0xdb8c, 0x43d4, { 0xb5, 0x40, 0x76, 0xc0, 0x4a, 0x39, 0xa7, 0xc7 } };
static const GUID GUID_CFG_SEARCH_SKIP_FILTER               = { 0x4c6e3dac, 0xb668, 0x4056, { 0x8c, 0xb7, 0x52, 0x89, 0x1a, 0x57, 0x1f, 0x3a } };
static const GUID GUID_CFG_SEARCH_PREFERRED_LYRIC_TYPE      = { 0x66b4edf6, 0x7995, 0x4d52, { 0xa9, 0x0a, 0x12, 0xdf, 0xf7, 0x0a, 0x11, 0xa2 } };
static const GUID GUID_CFG_SEARCH_WITHOUT_LYRIC_PANELS      = { 0x3d29b9eb, 0x4454, 0x4798, { 0x9b, 0x33, 0x4b, 0xb5, 0xbf, 0x44, 0x4a, 0x7f } };
static const GUID GUID_CFG_SEARCH_ACTIVE_SOURCES_GENERATION = { 0x9046aa4a, 0x352e, 0x4467, { 0xbc, 0xd2, 0xc4, 0x19, 0x47, 0xd2, 0xbf, 0x24 } };
static const GUID GUID_CFG_SEARCH_ACTIVE_SOURCES            = { 0x7d3c9b2c, 0xb87b, 0x4250, { 0x99, 0x56, 0x8d, 0xf5, 0x80, 0xc9, 0x2f, 0x39 } };
static const GUID GUID_CFG_SEARCH_TAGS                      = { 0xb7332708, 0xe70b, 0x4a6e, { 0xa4, 0x0d, 0x14, 0x6d, 0xe3, 0x74, 0x56, 0x65 } };
static const GUID GUID_CFG_SEARCH_MUSIXMATCH_TOKEN          = { 0xb88a82a7, 0x746d, 0x44f3, { 0xb8, 0x34, 0x9b, 0x9b, 0xe2, 0x6f, 0x08, 0x4c } };

// Saving
static const GUID GUID_CFG_SAVE_ENABLE_AUTOSAVE   = { 0xf25be2d9, 0x4442, 0x4602, { 0xa0, 0xf1, 0x81, 0x0d, 0x8e, 0xab, 0x6a, 0x02 } };
static const GUID GUID_CFG_SAVE_METHOD            = { 0xdf39b51c, 0xec55, 0x41aa, { 0x93, 0xd3, 0x32, 0xb6, 0xc0, 0x5d, 0x4f, 0xcc } };
static const GUID GUID_CFG_SAVE_MERGE_LRC_LINES   = { 0x97229606, 0x8fd5, 0x441a, { 0xa6, 0x84, 0x9f, 0x3d, 0x87, 0xc8, 0x27, 0x18 } };
static const GUID GUID_CFG_SAVE_DIR_CLASS         = { 0xcf49878d, 0xe2ea, 0x4682, { 0x98, 0x0b, 0x8f, 0xc1, 0xf3, 0x80, 0x46, 0x7b } };
static const GUID GUID_CFG_SAVE_FILENAME_FORMAT   = { 0x1f7a3804, 0x7147, 0x4b64, { 0x9d, 0x51, 0x4c, 0xdd, 0x90, 0xa7, 0x6d, 0xd6 } };
static const GUID GUID_CFG_SAVE_PATH_CUSTOM       = { 0x84ac099b, 0xa00b, 0x4713, { 0x8f, 0x1c, 0x30, 0x7e, 0x31, 0xc0, 0xa1, 0xdf } };
static const GUID GUID_CFG_SAVE_TAG_UNTIMED       = { 0x39b0bc08, 0x5c3a, 0x4359, { 0x9d, 0xdb, 0xd4, 0x90, 0x84, 0x0b, 0x31, 0x88 } };
static const GUID GUID_CFG_SAVE_TAG_TIMESTAMPED   = { 0x337d0d40, 0xe9da, 0x4531, { 0xb0, 0x82, 0x13, 0x24, 0x56, 0xe5, 0xc4, 0x02 } };

// Display
static const GUID GUID_CFG_DISPLAY_CUSTOM_FONT              = { 0x828be475, 0x8e26, 0x4504, { 0x87, 0x53, 0x22, 0xf5, 0x69, 0x0d, 0x53, 0xb7 } };
static const GUID GUID_CFG_DISPLAY_CUSTOM_FOREGROUND_COLOUR = { 0x675418e1, 0xe0b0, 0x4c85, { 0xbf, 0xde, 0x1c, 0x17, 0x9b, 0xbc, 0xca, 0xa7 } };
static const GUID GUID_CFG_DISPLAY_CUSTOM_HIGHLIGHT_COLOUR  = { 0xfa2fed99, 0x593c, 0x4828, { 0xbf, 0x7d, 0x95, 0x8e, 0x99, 0x26, 0x9d, 0xcb } };
static const GUID GUID_CFG_DISPLAY_FOREGROUND_COLOUR        = { 0x36724d22, 0xe51e, 0x4c84, { 0x9e, 0xb2, 0x58, 0xa4, 0xd8, 0x23, 0xb3, 0x67 } };
static const GUID GUID_CFG_DISPLAY_HIGHLIGHT_COLOUR         = { 0xfa16da6c, 0xb22d, 0x49cb, { 0x97, 0x53, 0x94, 0x8c, 0xec, 0xf8, 0x37, 0x35 } };
static const GUID GUID_CFG_DISPLAY_PASTTEXT_COLOUR          = { 0x8189faa4, 0x40f2, 0x464b, { 0x9e, 0x0b, 0x53, 0xd2, 0x06, 0x9c, 0x74, 0xc9 } };
static const GUID GUID_CFG_DISPLAY_PASTTEXT_COLOURTYPE      = { 0x0c7b2908, 0x2ce2, 0x46e8, { 0xa1, 0x46, 0x51, 0xe2, 0x60, 0x00, 0xde, 0xdc } };
static const GUID GUID_CFG_DISPLAY_LINEGAP                  = { 0x4cc61a5c, 0x58dd, 0x47ce, { 0xa9, 0x35, 0x09, 0xbb, 0xfa, 0xc6, 0x40, 0x43 } };
static const GUID GUID_CFG_DISPLAY_SCROLL_CONTINUOUS        = { 0x9ccfe1b0, 0x3c8a, 0x4f3d, { 0x91, 0x1f, 0x1e, 0x3e, 0xdf, 0x71, 0x88, 0xd7 } };
static const GUID GUID_CFG_DISPLAY_SCROLL_TIME              = { 0xc1c7dbf7, 0xd3ce, 0x40dc, { 0x83, 0x29, 0xed, 0xa0, 0xc6, 0xc8, 0xb6, 0x70 } };
static const GUID GUID_CFG_DISPLAY_SCROLL_TYPE              = { 0x3f2f17d8, 0x9309, 0x4721, { 0x9f, 0xa7, 0x79, 0x6d, 0x17, 0x84, 0x2a, 0x5d } };
static const GUID GUID_CFG_DISPLAY_HIGHLIGHT_FADE_TIME      = { 0x63c31bb9, 0x2a83, 0x4685, { 0xb4, 0x15, 0x64, 0xd6, 0x05, 0x85, 0xbd, 0xa8 } };
static const GUID GUID_CFG_DISPLAY_TEXT_ALIGNMENT           = { 0xfd228452, 0x6374, 0x4496, { 0xb9, 0xec, 0x19, 0xb9, 0x50, 0x02, 0x0b, 0xaa } };

// Background
static const GUID GUID_CFG_BACKGROUND_MODE                     = { 0xdcb91bea, 0x942b, 0x4f0b, { 0xbc, 0xcd, 0x2f, 0x22, 0xb2, 0xaa, 0x89, 0xa9 } };
static const GUID GUID_CFG_BACKGROUND_COLOUR_TYPE              = { 0x13da3237, 0xaa1d, 0x4065, { 0x82, 0xb0, 0xe4, 0x03, 0x31, 0xe0, 0x69, 0x5b } };
static const GUID GUID_CFG_BACKGROUND_COLOUR                   = { 0x7eaeeae6, 0xd41d, 0x4c0d, { 0x97, 0x86, 0x20, 0xa2, 0x8f, 0x27, 0x98, 0xd4 } };
static const GUID GUID_CFG_BACKGROUND_GRADIENT_TL              = { 0x9b9066b0, 0xcb2a, 0x457e, { 0xa6, 0x98, 0x38, 0x3a, 0x73, 0x28, 0x5d, 0x89 } };
static const GUID GUID_CFG_BACKGROUND_GRADIENT_TR              = { 0x5da8b259, 0x5d9d, 0x4ccc, { 0x9f, 0x5b, 0x48, 0xe9, 0x88, 0x7f, 0x89, 0xee } };
static const GUID GUID_CFG_BACKGROUND_GRADIENT_BL              = { 0x1d5eec1c, 0x4981, 0x4b20, { 0x87, 0xb5, 0xe6, 0xec, 0x1c, 0xb7, 0x1b, 0x7c } };
static const GUID GUID_CFG_BACKGROUND_GRADIENT_BR              = { 0x3c71b4fa, 0xe5a4, 0x46c6, { 0x92, 0x5c, 0xb2, 0x0a, 0x3f, 0x03, 0x10, 0x0c } };
static const GUID GUID_CFG_BACKGROUND_IMAGE_OPACITY            = { 0xf44e849f, 0x2f8f, 0x49cf, { 0x93, 0x06, 0x3a, 0x46, 0x76, 0x52, 0x5c, 0x3b } };
static const GUID GUID_CFG_BACKGROUND_BLUR_RADIUS              = { 0xe9419593, 0x46b7, 0x403e, { 0xa7, 0xcc, 0x64, 0xd9, 0xed, 0x5b, 0x4a, 0x5a } };
static const GUID GUID_CFG_BACKGROUND_MAINTAIN_IMG_ASPECT_RATIO = { 0xb031bbce, 0xdb0c, 0x468f, { 0x9f, 0x64, 0xf1, 0xe8, 0x0d, 0x5f, 0x02, 0x3c } };
static const GUID GUID_CFG_BACKGROUND_CUSTOM_IMAGE_PATH        = { 0xc8ef264b, 0xa679, 0x4a63, { 0x99, 0x06, 0xc2, 0x5b, 0xff, 0x49, 0x0e, 0x86 } };
static const GUID GUID_CFG_BACKGROUND_EXTERNALWIN_OPACITY      = { 0xd7937a05, 0xbf33, 0x4647, { 0x8b, 0x24, 0xf4, 0x88, 0xb6, 0xc0, 0xca, 0x76 } };

// Editing
static const GUID GUID_CFG_EDIT_AUTO_AUTO_EDITS = { 0x3b416210, 0x85fa, 0x4406, { 0xb5, 0xd6, 0x4b, 0x39, 0x72, 0x8e, 0xee, 0xab } };

// Upload
static const GUID GUID_CFG_UPLOAD_STRATEGY = { 0x28a7533a, 0x1f9c, 0x436e, { 0xba, 0xed, 0x0a, 0x6a, 0x59, 0x26, 0xc3, 0xc7 } };

// clang-format on

// ===========================================================================
// Default active sources (match Windows defaults)
// ===========================================================================

static const GUID localfiles_src_guid    = { 0x76d90970, 0x1c98, 0x4fe2, { 0x94, 0x4e, 0xac, 0xe4, 0x93, 0xf3, 0x8e, 0x85 } };
static const GUID metadata_tags_src_guid = { 0x3fb0f715, 0xa097, 0x493a, { 0x94, 0x4e, 0xdb, 0x48, 0x66, 0x08, 0x86, 0x78 } };
static const GUID qqmusic_src_guid       = { 0x4b0b5722, 0x3a84, 0x4b8e, { 0x82, 0x7a, 0x26, 0xb9, 0xea, 0xb3, 0xb4, 0xe8 } };
static const GUID netease_src_guid       = { 0xaac13215, 0xe32e, 0x4667, { 0xac, 0xd7, 0x1f, 0x0d, 0xbd, 0x84, 0x27, 0xe4 } };

static const GUID cfg_search_active_sources_default[] = {
    localfiles_src_guid,
    metadata_tags_src_guid,
    qqmusic_src_guid,
    netease_src_guid,
};

static const int cfg_edit_auto_auto_edits_default[] = {
    static_cast<int>(AutoEditType::ReplaceHtmlEscapedChars),
    static_cast<int>(AutoEditType::RemoveRepeatedSpaces),
};

// ===========================================================================
// cfg_* variable instances
// ===========================================================================

// Root / debug
static cfg_int cfg_debug_logs_enabled(GUID_CFG_DEBUG_LOGS_ENABLED, 0 /*false*/);

// Searching
static cfg_int    cfg_search_exclude_trailing_brackets(GUID_CFG_SEARCH_EXCLUDE_TRAILING_BRACKETS, 1 /*true*/);
static cfg_string cfg_search_skip_filter(
    GUID_CFG_SEARCH_SKIP_FILTER,
    "$if($strstr($lower(%genre%),instrumental),skip,)"
    "$if($strstr($lower(%genre%),classical),skip,)");
static cfg_int    cfg_search_preferred_lyric_type(GUID_CFG_SEARCH_PREFERRED_LYRIC_TYPE,
                                                  static_cast<int>(LyricType::Synced));
static cfg_int    cfg_search_without_lyric_panels(GUID_CFG_SEARCH_WITHOUT_LYRIC_PANELS, 0 /*false*/);
static cfg_int    cfg_search_active_sources_generation(GUID_CFG_SEARCH_ACTIVE_SOURCES_GENERATION, 0);
static cfg_var_modern::cfg_objList<GUID> cfg_search_active_sources(GUID_CFG_SEARCH_ACTIVE_SOURCES,
                                                                    cfg_search_active_sources_default);
static cfg_string cfg_search_tags(GUID_CFG_SEARCH_TAGS, "UNSYNCED LYRICS;LYRICS;SYNCEDLYRICS;UNSYNCEDLYRICS");
static cfg_string cfg_search_musixmatch_token(GUID_CFG_SEARCH_MUSIXMATCH_TOKEN, "");

// Saving
static cfg_int cfg_save_auto_save_strategy(GUID_CFG_SAVE_ENABLE_AUTOSAVE,
                                           static_cast<int>(AutoSaveStrategy::Always));
static cfg_int cfg_save_method(GUID_CFG_SAVE_METHOD, static_cast<int>(SaveMethod::LocalFile));
static cfg_int cfg_save_merge_lrc_lines(GUID_CFG_SAVE_MERGE_LRC_LINES, 1 /*true*/);
static cfg_int cfg_save_dir_class(GUID_CFG_SAVE_DIR_CLASS,
                                  static_cast<int>(SaveDirectoryClass::ConfigDirectory));
static cfg_string cfg_save_filename_format(
    GUID_CFG_SAVE_FILENAME_FORMAT,
    "$replace([%artist% - ][%title%],/,-,<,-,>,-,:,-,\",-,|,-,?,-,*,-)");
static cfg_string cfg_save_path_custom(GUID_CFG_SAVE_PATH_CUSTOM, "~/Music/Lyrics/%artist%");
static cfg_string cfg_save_tag_untimed(GUID_CFG_SAVE_TAG_UNTIMED, "UNSYNCED LYRICS");
static cfg_string cfg_save_tag_timestamped(GUID_CFG_SAVE_TAG_TIMESTAMPED, "UNSYNCED LYRICS");

// Display
static cfg_int cfg_display_custom_font(GUID_CFG_DISPLAY_CUSTOM_FONT, 0 /*false*/);
static cfg_int cfg_display_custom_fg_colour(GUID_CFG_DISPLAY_CUSTOM_FOREGROUND_COLOUR, 0);
static cfg_int cfg_display_custom_hl_colour(GUID_CFG_DISPLAY_CUSTOM_HIGHLIGHT_COLOUR, 0);
static cfg_int cfg_display_fg_colour(GUID_CFG_DISPLAY_FOREGROUND_COLOUR, RGB(35, 85, 125));
static cfg_int cfg_display_hl_colour(GUID_CFG_DISPLAY_HIGHLIGHT_COLOUR, RGB(225, 65, 60));
static cfg_int cfg_display_pasttext_colour(GUID_CFG_DISPLAY_PASTTEXT_COLOUR, RGB(190, 190, 190));
static cfg_int cfg_display_pasttext_colour_type(GUID_CFG_DISPLAY_PASTTEXT_COLOURTYPE,
                                                static_cast<int>(PastTextColourType::BlendBackground));
static cfg_int cfg_display_linegap(GUID_CFG_DISPLAY_LINEGAP, 4);
static cfg_int cfg_display_scroll_continuous(GUID_CFG_DISPLAY_SCROLL_CONTINUOUS, 0);
static cfg_int cfg_display_scroll_time(GUID_CFG_DISPLAY_SCROLL_TIME, 500);
static cfg_int cfg_display_scroll_type(GUID_CFG_DISPLAY_SCROLL_TYPE,
                                       static_cast<int>(LineScrollType::Automatic));
static cfg_int cfg_display_highlight_fade_time(GUID_CFG_DISPLAY_HIGHLIGHT_FADE_TIME, 500);
static cfg_int cfg_display_text_alignment(GUID_CFG_DISPLAY_TEXT_ALIGNMENT,
                                          static_cast<int>(TextAlignment::MidCentre));

// Background
static cfg_int cfg_background_fill_type(GUID_CFG_BACKGROUND_MODE,
                                        static_cast<int>(BackgroundFillType::Default));
static cfg_int cfg_background_image_type(GUID_CFG_BACKGROUND_COLOUR_TYPE,
                                         static_cast<int>(BackgroundImageType::None));
static cfg_int cfg_background_colour(GUID_CFG_BACKGROUND_COLOUR, RGB(255, 255, 255));
static cfg_int cfg_background_gradient_tl(GUID_CFG_BACKGROUND_GRADIENT_TL, RGB(11, 145, 255));
static cfg_int cfg_background_gradient_tr(GUID_CFG_BACKGROUND_GRADIENT_TR, RGB(166, 215, 255));
static cfg_int cfg_background_gradient_bl(GUID_CFG_BACKGROUND_GRADIENT_BL, RGB(100, 185, 255));
static cfg_int cfg_background_gradient_br(GUID_CFG_BACKGROUND_GRADIENT_BR, RGB(255, 255, 255));
static cfg_int cfg_background_image_opacity(GUID_CFG_BACKGROUND_IMAGE_OPACITY, 16);
static cfg_int cfg_background_blur_radius(GUID_CFG_BACKGROUND_BLUR_RADIUS, 6);
static cfg_int cfg_background_maintain_img_aspect_ratio(GUID_CFG_BACKGROUND_MAINTAIN_IMG_ASPECT_RATIO,
                                                        1 /*true*/);
static cfg_string cfg_background_custom_img_path(GUID_CFG_BACKGROUND_CUSTOM_IMAGE_PATH, "");
static cfg_int cfg_background_externalwin_opaque(GUID_CFG_BACKGROUND_EXTERNALWIN_OPACITY, 0 /*false*/);

// Editing
static cfg_var_modern::cfg_objList<int32_t> cfg_edit_auto_auto_edits(GUID_CFG_EDIT_AUTO_AUTO_EDITS,
                                                                      cfg_edit_auto_auto_edits_default);

// Upload
static cfg_int cfg_upload_strategy(GUID_CFG_UPLOAD_STRATEGY,
                                          static_cast<int>(UploadStrategy::Never));

// ===========================================================================
// preferences:: accessor implementations
// ===========================================================================

// --- defaultui stubs (macOS system-colour approximations) ---
namespace defaultui
{
    t_ui_font default_font()  { return nullptr; }
    t_ui_font console_font()  { return nullptr; }
    t_ui_color background_colour() { return RGB(30, 30, 30);  }
    t_ui_color text_colour()       { return RGB(220, 220, 220); }
    t_ui_color highlight_colour()  { return RGB(0, 191, 255);  }
}

// --- searching ---
uint64_t preferences::searching::source_config_generation()
{
    return cfg_search_active_sources_generation.get_value();
}

std::vector<GUID> preferences::searching::active_sources()
{
    GUID save_src = preferences::saving::save_source();
    bool save_src_seen = false;

    const size_t count = cfg_search_active_sources.get_size();
    std::vector<GUID> result;
    result.reserve(count + 1);
    for(size_t i = 0; i < count; i++)
    {
        save_src_seen |= (save_src == cfg_search_active_sources[i]);
        result.push_back(cfg_search_active_sources[i]);
    }
    if(!save_src_seen && (save_src != GUID {}))
        result.push_back(save_src);
    return result;
}

std::vector<GUID> preferences::searching::raw::active_sources_configured()
{
    const size_t count = cfg_search_active_sources.get_size();
    std::vector<GUID> result;
    result.reserve(count);
    for(size_t i = 0; i < count; i++)
        result.push_back(cfg_search_active_sources[i]);
    return result;
}

bool preferences::searching::exclude_trailing_brackets()
{
    return cfg_search_exclude_trailing_brackets.get_value() != 0;
}

const pfc::string8& preferences::searching::skip_filter()
{
    static pfc::string8 s;
    cfg_search_skip_filter.get(s);
    return s;
}

bool preferences::searching::raw::is_skip_filter_default()
{
    const pfc::string8 cur = cfg_search_skip_filter.get();
    const std::string_view def = "$if($strstr($lower(%genre%),instrumental),skip,)"
                                 "$if($strstr($lower(%genre%),classical),skip,)";
    return std::string_view(cur.c_str(), cur.get_length()) == def;
}

LyricType preferences::searching::preferred_lyric_type()
{
    return static_cast<LyricType>(cfg_search_preferred_lyric_type.get_value());
}

bool preferences::searching::should_search_without_panels()
{
    return cfg_search_without_lyric_panels.get_value() != 0;
}

std::vector<std::string> preferences::searching::tags()
{
    const pfc::string8 setting_str = cfg_search_tags.get();
    const std::string_view setting { setting_str.c_str(), setting_str.get_length() };
    std::vector<std::string> result;
    size_t prev = 0;
    for(size_t i = 0; i <= setting.length(); i++)
    {
        if(i == setting.length() || setting[i] == ';')
        {
            size_t len = i - prev;
            if(len > 0)
                result.emplace_back(setting.substr(prev, len));
            prev = i + 1;
        }
    }
    return result;
}

std::string_view preferences::searching::musixmatch_api_key()
{
    static pfc::string8 s;
    cfg_search_musixmatch_token.get(s);
    return { s.c_str(), s.get_length() };
}

// --- editing ---
std::vector<AutoEditType> preferences::editing::automated_auto_edits()
{
    const size_t count = cfg_edit_auto_auto_edits.get_size();
    std::vector<AutoEditType> result;
    result.reserve(count);
    for(size_t i = 0; i < count; i++)
        result.push_back(static_cast<AutoEditType>(cfg_edit_auto_auto_edits[i]));
    return result;
}

// --- saving ---
AutoSaveStrategy preferences::saving::autosave_strategy()
{
    return static_cast<AutoSaveStrategy>(cfg_save_auto_save_strategy.get_value());
}

GUID preferences::saving::save_source()
{
    const GUID id3tag_src_guid = { 0x3fb0f715, 0xa097, 0x493a,
                                   { 0x94, 0x4e, 0xdb, 0x48, 0x66, 0x08, 0x86, 0x78 } };
    SaveMethod method = static_cast<SaveMethod>(cfg_save_method.get_value());
    if(method == SaveMethod::Id3Tag)
        return id3tag_src_guid;
    return localfiles_src_guid;
}

bool preferences::saving::merge_equivalent_lrc_lines()
{
    return cfg_save_merge_lrc_lines.get_value() != 0;
}

std::string preferences::saving::filename(metadb_handle_ptr track, const metadb_v2_rec_t& track_info)
{
    const pfc::string8 fmt_s = cfg_save_filename_format.get();
    const char* name_format_str = fmt_s.c_str();
    titleformat_object::ptr name_script;
    if(!titleformat_compiler::get()->compile(name_script, name_format_str))
    {
        LOG_WARN("Failed to compile save file format: %s", name_format_str);
        return {};
    }

    pfc::string8 formatted_name;
    track->formatTitle_v2_(track_info, nullptr, formatted_name, name_script, nullptr);

    pfc::string8 formatted_directory;
    const SaveDirectoryClass dir_class =
        track_is_remote(track) ? SaveDirectoryClass::ConfigDirectory
                               : static_cast<SaveDirectoryClass>(cfg_save_dir_class.get_value());

    switch(dir_class)
    {
        case SaveDirectoryClass::ConfigDirectory:
        {
            formatted_directory = core_api::get_profile_path();
            formatted_directory.add_filename("lyrics");
        }
        break;

        case SaveDirectoryClass::TrackFileDirectory:
        {
            formatted_directory = pfc::io::path::getParent(track->get_path()).c_str();
        }
        break;

        case SaveDirectoryClass::Custom:
        {
            const pfc::string8 path_s = cfg_save_path_custom.get();
            const char* path_fmt = path_s.c_str();
            titleformat_object::ptr dir_script;
            if(!titleformat_compiler::get()->compile(dir_script, path_fmt))
            {
                LOG_WARN("Failed to compile save path format: %s", path_fmt);
                return {};
            }
            pfc::string8 formatted_dir;
            if(!track->format_title(nullptr, formatted_dir, dir_script, nullptr))
            {
                LOG_WARN("Failed to format save path: %s", path_fmt);
                return {};
            }
            formatted_directory = formatted_dir;
        }
        break;

        default:
            LOG_WARN("Unrecognised save dir class: %d", static_cast<int>(dir_class));
            return {};
    }

    pfc::string8 formatted_path = formatted_directory;
    formatted_path.add_filename(formatted_name);

    pfc::string8 native_path;
    filesystem::g_get_native_path(formatted_path, native_path);

    if(formatted_directory.is_empty() || formatted_name.is_empty())
    {
        LOG_WARN("Invalid save path: %s", native_path.c_str());
        return {};
    }

#ifdef __APPLE__
    // g_get_native_path strips the "file://" prefix, but SDK filesystem APIs on macOS
    // require file:// URIs (bare POSIX paths are not handled by the local filesystem service).
    // Re-wrap bare POSIX paths so all downstream SDK calls receive a valid URI.
    if(native_path.get_ptr()[0] == '/')
    {
        pfc::string8 file_uri = "file://";
        file_uri += native_path.get_ptr();
        return std::string(file_uri.c_str(), file_uri.length());
    }
#endif

    return std::string(native_path.c_str(), native_path.length());
}

std::string_view preferences::saving::untimed_tag()
{
    static pfc::string8 s;
    cfg_save_tag_untimed.get(s);
    return { s.c_str(), s.get_length() };
}

std::string_view preferences::saving::timestamped_tag()
{
    static pfc::string8 s;
    cfg_save_tag_timestamped.get(s);
    return { s.c_str(), s.get_length() };
}

SaveDirectoryClass preferences::saving::raw::directory_class()
{
    return static_cast<SaveDirectoryClass>(cfg_save_dir_class.get_value());
}

// --- display ---
t_ui_font preferences::display::font()
{
    return nullptr; // Custom font selection deferred; macOS uses host NSFont
}

t_ui_color preferences::display::main_text_colour()
{
    if(cfg_display_custom_fg_colour.get_value())
        return (t_ui_color)cfg_display_fg_colour.get_value();
    return defaultui::text_colour();
}

t_ui_color preferences::display::highlight_colour()
{
    if(cfg_display_custom_hl_colour.get_value())
        return (t_ui_color)cfg_display_hl_colour.get_value();
    return defaultui::highlight_colour();
}

t_ui_color preferences::display::past_text_colour()
{
    switch(static_cast<PastTextColourType>(cfg_display_pasttext_colour_type.get_value()))
    {
        case PastTextColourType::BlendBackground:
        {
            RGBAColour bg = {};
            switch(static_cast<BackgroundFillType>(cfg_background_fill_type.get_value()))
            {
                case BackgroundFillType::Default:
                    bg = colorref_to_rgba(defaultui::background_colour()); break;
                case BackgroundFillType::SolidColour:
                    bg = colorref_to_rgba((uint32_t)cfg_background_colour.get_value()); break;
                case BackgroundFillType::Gradient:
                {
                    RGBAColour tl = colorref_to_rgba((uint32_t)cfg_background_gradient_tl.get_value());
                    RGBAColour tr = colorref_to_rgba((uint32_t)cfg_background_gradient_tr.get_value());
                    bg = lerp_colour(tl, tr, 127);
                }
                break;
            }
            RGBAColour fg = colorref_to_rgba(main_text_colour());
            RGBAColour blended = lerp_colour(fg, bg, 190);
            return rgba_to_colorref(blended.r, blended.g, blended.b);
        }
        case PastTextColourType::SameAsMainText:  return main_text_colour();
        case PastTextColourType::SameAsHighlight: return highlight_colour();
        case PastTextColourType::Custom:          return (t_ui_color)cfg_display_pasttext_colour.get_value();
        default:                                  return defaultui::text_colour();
    }
}

LineScrollType preferences::display::scroll_type()
{
    return static_cast<LineScrollType>(cfg_display_scroll_type.get_value());
}

double preferences::display::scroll_time_seconds()
{
    if(cfg_display_scroll_continuous.get_value())
        return DBL_MAX;
    return static_cast<double>(cfg_display_scroll_time.get_value()) / 1000.0;
}

TextAlignment preferences::display::text_alignment()
{
    return static_cast<TextAlignment>(cfg_display_text_alignment.get_value());
}

double preferences::display::highlight_fade_seconds()
{
    return static_cast<double>(cfg_display_highlight_fade_time.get_value()) / 1000.0;
}

int preferences::display::linegap()
{
    return (int)cfg_display_linegap.get_value();
}

bool preferences::display::debug_logs_enabled()
{
    return cfg_debug_logs_enabled.get_value() != 0;
}

bool preferences::display::raw::font_is_custom()
{
    return cfg_display_custom_font.get_value() != 0;
}

// --- background ---
BackgroundFillType preferences::background::fill_type()
{
    return static_cast<BackgroundFillType>(cfg_background_fill_type.get_value());
}

BackgroundImageType preferences::background::image_type()
{
    return static_cast<BackgroundImageType>(cfg_background_image_type.get_value());
}

t_ui_color preferences::background::colour()
{
    return (t_ui_color)cfg_background_colour.get_value();
}

t_ui_color preferences::background::gradient_tl()
{
    return (t_ui_color)cfg_background_gradient_tl.get_value();
}

t_ui_color preferences::background::gradient_tr()
{
    return (t_ui_color)cfg_background_gradient_tr.get_value();
}

t_ui_color preferences::background::gradient_bl()
{
    return (t_ui_color)cfg_background_gradient_bl.get_value();
}

t_ui_color preferences::background::gradient_br()
{
    return (t_ui_color)cfg_background_gradient_br.get_value();
}

bool preferences::background::maintain_img_aspect_ratio()
{
    return cfg_background_maintain_img_aspect_ratio.get_value() != 0;
}

double preferences::background::image_opacity()
{
    return static_cast<double>(cfg_background_image_opacity.get_value()) / 100.0;
}

int preferences::background::blur_radius()
{
    return (int)cfg_background_blur_radius.get_value();
}

std::string preferences::background::custom_image_path()
{
    const pfc::string8 s = cfg_background_custom_img_path.get();
    return std::string(s.c_str(), s.get_length());
}

bool preferences::background::external_window_opaque()
{
    return cfg_background_externalwin_opaque.get_value() != 0;
}

// --- upload ---
UploadStrategy preferences::upload::lrclib_upload_strategy()
{
    return static_cast<UploadStrategy>(cfg_upload_strategy.get_value());
}

// ===========================================================================
// Migrate broken skip filter default (matches Windows fix_skip_filter_default_on_init)
// ===========================================================================

static void fix_skip_filter_default_on_init()
{
    const std::string_view old_broken = "$stricmp(%genre%,instrumental))$stricmp(%genre%,classical)";
    const std::string_view new_fixed  = "$if($strstr($lower(%genre%),instrumental),skip,)"
                                        "$if($strstr($lower(%genre%),classical),skip,)";
    const pfc::string8 current_s = cfg_search_skip_filter.get();
    const std::string_view current { current_s.c_str(), current_s.get_length() };
    if(current == old_broken)
        cfg_search_skip_filter.set(new_fixed.data());
}
FB2K_RUN_ON_INIT(fix_skip_filter_default_on_init)

// ===========================================================================
// Preference page NSViewController implementations
// ===========================================================================

// ---------------------------------------------------------------------------
// Helper: build a simple form inside an NSView using NSStackView
// ---------------------------------------------------------------------------

static NSTextField* make_label(NSString* text)
{
    NSTextField* tf = [NSTextField labelWithString:text];
    tf.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return tf;
}

static NSTextField* make_field(NSString* placeholder)
{
    NSTextField* tf = [[NSTextField alloc] init];
    tf.placeholderString = placeholder;
    tf.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    tf.bezelStyle = NSTextFieldSquareBezel;
    tf.bordered = YES;
    return tf;
}

static NSButton* make_checkbox(NSString* title)
{
    return [NSButton checkboxWithTitle:title target:nil action:nil];
}

static NSPopUpButton* make_popup(NSArray<NSString*>* items)
{
    NSPopUpButton* btn = [[NSPopUpButton alloc] init];
    [btn addItemsWithTitles:items];
    return btn;
}

static NSView* make_row(NSString* labelText, NSView* control)
{
    NSTextField* lbl = make_label(labelText);
    lbl.alignment = NSTextAlignmentRight;
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    control.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView* row = [NSStackView stackViewWithViews:@[lbl, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    [NSLayoutConstraint activateConstraints:@[
        [lbl.widthAnchor constraintEqualToConstant:160],
    ]];
    return row;
}

static NSStackView* make_form(NSArray<NSView*>* rows)
{
    NSStackView* stack = [[NSStackView alloc] init];
    stack.orientation  = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment    = NSLayoutAttributeLeading;
    stack.spacing      = 8;
    stack.edgeInsets   = NSEdgeInsetsMake(12, 12, 12, 12);
    // NSStackViewGravityTop pins rows to the visual top regardless of whether
    // the host view is flipped, so content stays at the top of the pane.
    [stack setViews:rows inGravity:NSStackViewGravityTop];
    return stack;
}

// ---------------------------------------------------------------------------
// Shared color-conversion helpers
// ---------------------------------------------------------------------------

static NSColor* nscolor_from_colorref(uint32_t c)
{
    return [NSColor colorWithRed:(c & 0xFF) / 255.0
                           green:((c >> 8) & 0xFF) / 255.0
                            blue:((c >> 16) & 0xFF) / 255.0
                           alpha:1.0];
}

static uint32_t colorref_from_nscolor(NSColor* color)
{
    NSColor* rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) rgb = color;
    return rgba_to_colorref((uint8_t)(rgb.redComponent * 255),
                            (uint8_t)(rgb.greenComponent * 255),
                            (uint8_t)(rgb.blueComponent * 255));
}

static NSColorWell* make_colorwell(uint32_t colorref, id target, SEL action)
{
    NSColorWell* w = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
    w.color = nscolor_from_colorref(colorref);
    w.target = target;
    w.action = action;
    return w;
}

// ---------------------------------------------------------------------------
// Root page: general / debug
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsRootVC : NSViewController
@property (nonatomic, weak) NSButton* debugLogsCheck;
@end

@implementation OpenLyricsPrefsRootVC

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    return self;
}

- (void)loadView
{
    _debugLogsCheck = make_checkbox(@"Enable debug logging");
    _debugLogsCheck.state = cfg_debug_logs_enabled.get_value() ? NSControlStateValueOn
                                                               : NSControlStateValueOff;
    [_debugLogsCheck setTarget:self];
    [_debugLogsCheck setAction:@selector(onDebugLogs:)];

    NSTextField* note = [NSTextField wrappingLabelWithString:
        @"Select sub-pages in the tree on the left to configure searching, saving, and display."];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView* stack = make_form(@[note, _debugLogsCheck]);
    stack.frame = NSMakeRect(0, 0, 500, 200);
    self.view = stack;
}

- (void)onDebugLogs:(NSButton*)sender
{
    cfg_debug_logs_enabled = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

@end

// ---------------------------------------------------------------------------
// Searching page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsSearchVC : NSViewController
@end

@implementation OpenLyricsPrefsSearchVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    // Preferred lyric type
    NSPopUpButton* typePopup = make_popup(@[@"Synced", @"Unsynced"]);
    typePopup.tag = 0;
    int typeVal = (int)cfg_search_preferred_lyric_type.get_value();
    [typePopup selectItemAtIndex:typeVal == static_cast<int>(LyricType::Synced) ? 0 : 1];
    [typePopup setTarget:self];
    [typePopup setAction:@selector(onLyricType:)];

    // Exclude trailing brackets
    NSButton* excludeCheck = make_checkbox(@"Exclude trailing brackets from search terms");
    excludeCheck.state = cfg_search_exclude_trailing_brackets.get_value()
                             ? NSControlStateValueOn : NSControlStateValueOff;
    [excludeCheck setTarget:self];
    [excludeCheck setAction:@selector(onExcludeBrackets:)];

    // Search without panels
    NSButton* noPanelsCheck = make_checkbox(@"Search for lyrics even when no panel is visible");
    noPanelsCheck.state = cfg_search_without_lyric_panels.get_value()
                              ? NSControlStateValueOn : NSControlStateValueOff;
    [noPanelsCheck setTarget:self];
    [noPanelsCheck setAction:@selector(onSearchWithoutPanels:)];

    // Skip filter
    NSTextField* skipField = make_field(@"titleformat expression");
    skipField.stringValue = [NSString stringWithUTF8String:cfg_search_skip_filter.get().c_str()];
    skipField.tag = 1;
    skipField.target = self;
    skipField.action = @selector(onSkipFilter:);

    NSStackView* stack = make_form(@[
        make_row(@"Preferred type:", typePopup),
        excludeCheck,
        noPanelsCheck,
        make_row(@"Skip filter:", skipField),
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 240);
    self.view = stack;
}

- (void)onLyricType:(NSPopUpButton*)sender
{
    cfg_search_preferred_lyric_type = (sender.indexOfSelectedItem == 0)
                                          ? static_cast<int>(LyricType::Synced)
                                          : static_cast<int>(LyricType::Unsynced);
}

- (void)onExcludeBrackets:(NSButton*)sender
{
    cfg_search_exclude_trailing_brackets = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

- (void)onSearchWithoutPanels:(NSButton*)sender
{
    cfg_search_without_lyric_panels = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

- (void)onSkipFilter:(NSTextField*)sender
{
    const char* str = sender.stringValue.UTF8String;
    cfg_search_skip_filter.set(str ? str : "");
}

@end

// ---------------------------------------------------------------------------
// Saving page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsSavingVC : NSViewController
@end

@implementation OpenLyricsPrefsSavingVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    // Autosave strategy
    NSPopUpButton* autosavePopup = make_popup(@[
        @"Always",
        @"Only synced lyrics",
        @"Only unsynced lyrics",
        @"Never",
    ]);
    int stratVal = (int)cfg_save_auto_save_strategy.get_value();
    int autosaveIdx = 0;
    if(stratVal == static_cast<int>(AutoSaveStrategy::Always))        autosaveIdx = 0;
    else if(stratVal == static_cast<int>(AutoSaveStrategy::OnlySynced))   autosaveIdx = 1;
    else if(stratVal == static_cast<int>(AutoSaveStrategy::OnlyUnsynced)) autosaveIdx = 2;
    else if(stratVal == static_cast<int>(AutoSaveStrategy::Never))        autosaveIdx = 3;
    [autosavePopup selectItemAtIndex:autosaveIdx];
    [autosavePopup setTarget:self];
    [autosavePopup setAction:@selector(onAutosave:)];

    // Save method
    NSPopUpButton* methodPopup = make_popup(@[@"Save to text file", @"Save to tag"]);
    int methodIdx = (cfg_save_method.get_value() == static_cast<int>(SaveMethod::Id3Tag)) ? 1 : 0;
    [methodPopup selectItemAtIndex:methodIdx];
    [methodPopup setTarget:self];
    [methodPopup setAction:@selector(onSaveMethod:)];

    // Save directory
    NSPopUpButton* dirPopup = make_popup(@[
        @"foobar2000 configuration directory",
        @"Same directory as the track",
        @"Custom directory",
    ]);
    int dirVal = (int)cfg_save_dir_class.get_value();
    int dirIdx = 0;
    if(dirVal == static_cast<int>(SaveDirectoryClass::ConfigDirectory))    dirIdx = 0;
    else if(dirVal == static_cast<int>(SaveDirectoryClass::TrackFileDirectory)) dirIdx = 1;
    else if(dirVal == static_cast<int>(SaveDirectoryClass::Custom))             dirIdx = 2;
    [dirPopup selectItemAtIndex:dirIdx];
    [dirPopup setTarget:self];
    [dirPopup setAction:@selector(onSaveDir:)];

    // Merge LRC lines
    NSButton* mergeCheck = make_checkbox(@"Merge equivalent LRC lines");
    mergeCheck.state = cfg_save_merge_lrc_lines.get_value() ? NSControlStateValueOn
                                                            : NSControlStateValueOff;
    [mergeCheck setTarget:self];
    [mergeCheck setAction:@selector(onMergeLrc:)];

    // Filename format
    NSTextField* fmtField = make_field(@"titleformat filename");
    fmtField.stringValue = [NSString stringWithUTF8String:cfg_save_filename_format.get().c_str()];
    fmtField.target = self;
    fmtField.action = @selector(onFilenameFormat:);

    NSStackView* stack = make_form(@[
        make_row(@"Autosave:", autosavePopup),
        make_row(@"Save method:", methodPopup),
        make_row(@"Save directory:", dirPopup),
        make_row(@"Filename format:", fmtField),
        mergeCheck,
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 260);
    self.view = stack;
}

- (void)onAutosave:(NSPopUpButton*)sender
{
    static const AutoSaveStrategy strats[] = {
        AutoSaveStrategy::Always,
        AutoSaveStrategy::OnlySynced,
        AutoSaveStrategy::OnlyUnsynced,
        AutoSaveStrategy::Never,
    };
    NSInteger idx = sender.indexOfSelectedItem;
    if(idx >= 0 && idx < 4)
        cfg_save_auto_save_strategy = static_cast<int>(strats[idx]);
}

- (void)onSaveMethod:(NSPopUpButton*)sender
{
    cfg_save_method = sender.indexOfSelectedItem == 1
                          ? static_cast<int>(SaveMethod::Id3Tag)
                          : static_cast<int>(SaveMethod::LocalFile);
}

- (void)onSaveDir:(NSPopUpButton*)sender
{
    static const SaveDirectoryClass classes[] = {
        SaveDirectoryClass::ConfigDirectory,
        SaveDirectoryClass::TrackFileDirectory,
        SaveDirectoryClass::Custom,
    };
    NSInteger idx = sender.indexOfSelectedItem;
    if(idx >= 0 && idx < 3)
        cfg_save_dir_class = static_cast<int>(classes[idx]);
}

- (void)onMergeLrc:(NSButton*)sender
{
    cfg_save_merge_lrc_lines = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

- (void)onFilenameFormat:(NSTextField*)sender
{
    const char* str = sender.stringValue.UTF8String;
    cfg_save_filename_format.set(str ? str : "");
}

@end

// ---------------------------------------------------------------------------
// Background page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsBackgroundVC : NSViewController
{
    NSTextField* _imgPathField;
}
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
    NSColorWell* colourWell = make_colorwell((uint32_t)cfg_background_colour.get_value(),
                                             self, @selector(onSolidColour:));

    // Gradient colour wells
    NSColorWell* gradTL = make_colorwell((uint32_t)cfg_background_gradient_tl.get_value(),
                                         self, @selector(onGradient:));
    gradTL.tag = 0;
    NSColorWell* gradTR = make_colorwell((uint32_t)cfg_background_gradient_tr.get_value(),
                                         self, @selector(onGradient:));
    gradTR.tag = 1;
    NSColorWell* gradBL = make_colorwell((uint32_t)cfg_background_gradient_bl.get_value(),
                                         self, @selector(onGradient:));
    gradBL.tag = 2;
    NSColorWell* gradBR = make_colorwell((uint32_t)cfg_background_gradient_br.get_value(),
                                         self, @selector(onGradient:));
    gradBR.tag = 3;

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
    _imgPathField = make_field(@"path to image");
    _imgPathField.stringValue = [NSString stringWithUTF8String:
        cfg_background_custom_img_path.get().c_str()];
    _imgPathField.target = self;
    _imgPathField.action = @selector(onCustomPath:);

    NSButton* browseBtn = [NSButton buttonWithTitle:@"Browse..."
                                             target:self action:@selector(onBrowseImage:)];

    NSStackView* pathRow = [NSStackView stackViewWithViews:@[_imgPathField, browseBtn]];
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

- (void)onFillType:(NSPopUpButton*)sender
{
    cfg_background_fill_type = (int)sender.indexOfSelectedItem;
    recompute_lyric_panel_backgrounds();
}

- (void)onSolidColour:(NSColorWell*)sender
{
    cfg_background_colour = (int)colorref_from_nscolor(sender.color);
    recompute_lyric_panel_backgrounds();
}

- (void)onGradient:(NSColorWell*)sender
{
    uint32_t c = colorref_from_nscolor(sender.color);
    switch (sender.tag) {
        case 0: cfg_background_gradient_tl = (int)c; break;
        case 1: cfg_background_gradient_tr = (int)c; break;
        case 2: cfg_background_gradient_bl = (int)c; break;
        case 3: cfg_background_gradient_br = (int)c; break;
    }
    recompute_lyric_panel_backgrounds();
}

- (void)onImageType:(NSPopUpButton*)sender
{
    cfg_background_image_type = (int)sender.indexOfSelectedItem;
    recompute_lyric_panel_backgrounds();
}

- (void)onOpacity:(NSSlider*)sender
{
    cfg_background_image_opacity = (int)sender.intValue;
    recompute_lyric_panel_backgrounds();
}

- (void)onBlur:(NSSlider*)sender
{
    cfg_background_blur_radius = (int)sender.intValue;
    recompute_lyric_panel_backgrounds();
}

- (void)onAspectRatio:(NSButton*)sender
{
    cfg_background_maintain_img_aspect_ratio = (sender.state == NSControlStateValueOn) ? 1 : 0;
    recompute_lyric_panel_backgrounds();
}

- (void)onCustomPath:(NSTextField*)sender
{
    const char* s = sender.stringValue.UTF8String;
    cfg_background_custom_img_path.set(s ? s : "");
    recompute_lyric_panel_backgrounds();
}

- (void)onBrowseImage:(NSButton*)__unused sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"gif", @"bmp", @"tiff", @"tif", @"webp"];
#pragma clang diagnostic pop
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        cfg_background_custom_img_path.set(panel.URL.path.UTF8String);
        _imgPathField.stringValue = panel.URL.path;
        recompute_lyric_panel_backgrounds();
    }
}

- (void)onExtOpaque:(NSButton*)sender
{
    cfg_background_externalwin_opaque = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

@end

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
        { AutoEditType::RemoveRepeatedSpaces,        @"Remove repeated spaces" },
        { AutoEditType::RemoveSurroundingWhitespace, @"Remove surrounding whitespace from each line" },
        { AutoEditType::RemoveRepeatedBlankLines,    @"Remove repeated blank lines" },
        { AutoEditType::RemoveAllBlankLines,         @"Remove all blank lines" },
        { AutoEditType::ResetCapitalisation,         @"Reset capitalisation" },
        { AutoEditType::FixMalformedTimestamps,      @"Fix malformed timestamps" },
        { AutoEditType::RemoveTimestamps,            @"Remove timestamps" },
    };

    std::vector<int32_t> enabledVec = cfg_edit_auto_auto_edits.get();
    std::set<int> enabled(enabledVec.begin(), enabledVec.end());

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

- (void)onToggleEdit:(NSButton*)__unused sender
{
    NSStackView* form = (NSStackView*)self.view;
    std::vector<int32_t> newList;
    for (NSView* v in form.arrangedSubviews) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* cb = (NSButton*)v;
            if (cb.state == NSControlStateValueOn)
                newList.push_back((int32_t)cb.tag);
        }
    }
    cfg_edit_auto_auto_edits.set_items(newList);
}

@end

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

    _activeTable = [self makeSourceTable];
    _activeTable.tag = 0;
    NSScrollView* activeScroll = [self wrapInScrollView:_activeTable height:160];

    _inactiveTable = [self makeSourceTable];
    _inactiveTable.tag = 1;
    NSScrollView* inactiveScroll = [self wrapInScrollView:_inactiveTable height:120];

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
    _activeSources = cfg_search_active_sources.get();

    _inactiveSources.clear();
    for (const GUID& guid : LyricSourceBase::get_all_ids()) {
        bool isActive = false;
        for (const GUID& active : _activeSources) {
            if (active == guid) { isActive = true; break; }
        }
        if (!isActive)
            _inactiveSources.push_back(guid);
    }
}

- (void)saveActiveSources
{
    cfg_search_active_sources.set_items(_activeSources);
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

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv
{
    return (tv.tag == 0) ? (NSInteger)_activeSources.size()
                         : (NSInteger)_inactiveSources.size();
}

- (NSView*)tableView:(NSTableView*)tv viewForTableColumn:(NSTableColumn*)__unused col row:(NSInteger)row
{
    NSTextField* cell = [NSTextField labelWithString:
        (tv.tag == 0) ? [self nameForSource:_activeSources[row]]
                      : [self nameForSource:_inactiveSources[row]]];
    cell.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return cell;
}

- (void)onMoveUp:(id)__unused sender
{
    NSInteger row = _activeTable.selectedRow;
    if (row <= 0) return;
    std::swap(_activeSources[row], _activeSources[row - 1]);
    [self saveActiveSources];
    [_activeTable reloadData];
    [_activeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
}

- (void)onMoveDown:(id)__unused sender
{
    NSInteger row = _activeTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_activeSources.size() - 1) return;
    std::swap(_activeSources[row], _activeSources[row + 1]);
    [self saveActiveSources];
    [_activeTable reloadData];
    [_activeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
}

- (void)onDeactivate:(id)__unused sender
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

- (void)onActivate:(id)__unused sender
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

// ---------------------------------------------------------------------------
// Local Files sub-page (under Search Sources)
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsLocalFilesVC : NSViewController
@end

@implementation OpenLyricsPrefsLocalFilesVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    NSPopUpButton* dirPopup = make_popup(@[
        @"foobar2000 configuration directory",
        @"Same directory as the track",
        @"Custom directory",
    ]);
    {
        int dirVal = (int)cfg_save_dir_class.get_value();
        int dirIdx = 0;
        if(dirVal == static_cast<int>(SaveDirectoryClass::ConfigDirectory))         dirIdx = 0;
        else if(dirVal == static_cast<int>(SaveDirectoryClass::TrackFileDirectory)) dirIdx = 1;
        else if(dirVal == static_cast<int>(SaveDirectoryClass::Custom))             dirIdx = 2;
        [dirPopup selectItemAtIndex:dirIdx];
    }
    [dirPopup setTarget:self];
    [dirPopup setAction:@selector(onDirClass:)];

    NSTextField* fmtField = make_field(@"titleformat filename");
    fmtField.stringValue = [NSString stringWithUTF8String:cfg_save_filename_format.get().c_str()];
    fmtField.target = self;
    fmtField.action = @selector(onFilenameFormat:);

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
    static const SaveDirectoryClass classes[] = {
        SaveDirectoryClass::ConfigDirectory,
        SaveDirectoryClass::TrackFileDirectory,
        SaveDirectoryClass::Custom,
    };
    NSInteger idx = sender.indexOfSelectedItem;
    if(idx >= 0 && idx < 3)
        cfg_save_dir_class = static_cast<int>(classes[idx]);
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

// ---------------------------------------------------------------------------
// Metadata Tags sub-page (under Search Sources)
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsMetaTagsVC : NSViewController
@end

@implementation OpenLyricsPrefsMetaTagsVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    NSTextField* tagsField = make_field(@"UNSYNCED LYRICS;LYRICS;...");
    tagsField.stringValue = [NSString stringWithUTF8String:cfg_search_tags.get().c_str()];
    tagsField.target = self;
    tagsField.action = @selector(onSearchTags:);

    NSTextField* untimedField = make_field(@"tag name");
    untimedField.stringValue = [NSString stringWithUTF8String:cfg_save_tag_untimed.get().c_str()];
    untimedField.target = self;
    untimedField.action = @selector(onUntimedTag:);

    NSTextField* timedField = make_field(@"tag name");
    timedField.stringValue = [NSString stringWithUTF8String:cfg_save_tag_timestamped.get().c_str()];
    timedField.target = self;
    timedField.action = @selector(onTimedTag:);

    NSTextField* note = [NSTextField wrappingLabelWithString:
        @"Search tags: semicolon-separated list of metadata fields to search for lyrics.\n"
        @"Save tags: which metadata field to write lyrics to when saving to tag.\n"
        @"\"UNSYNCED LYRICS\" writes to the ID3 USLT frame."];
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

// ---------------------------------------------------------------------------
// Musixmatch sub-page (under Search Sources)
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsMusixmatchVC : NSViewController
@property (nonatomic, weak) NSSecureTextField* secureField;
@property (nonatomic, weak) NSTextField* plainField;
@property (nonatomic, assign) BOOL tokenVisible;
@end

@implementation OpenLyricsPrefsMusixmatchVC

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    _tokenVisible = NO;
    return self;
}

- (void)loadView
{
    NSString* token = [NSString stringWithUTF8String:cfg_search_musixmatch_token.get().c_str()];

    NSSecureTextField* secField = [[NSSecureTextField alloc] init];
    secField.placeholderString = @"Musixmatch user token";
    secField.stringValue = token;
    secField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    secField.target = self;
    secField.action = @selector(onToken:);
    _secureField = secField;

    NSTextField* plainF = make_field(@"Musixmatch user token");
    plainF.stringValue = token;
    plainF.target = self;
    plainF.action = @selector(onToken:);
    plainF.hidden = YES;
    _plainField = plainF;

    NSStackView* fieldStack = [NSStackView stackViewWithViews:@[secField, plainF]];
    fieldStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    fieldStack.spacing = 0;

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

// ---------------------------------------------------------------------------
// Display page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsDisplayVC : NSViewController
@end

@implementation OpenLyricsPrefsDisplayVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    // Text alignment
    NSPopUpButton* alignPopup = make_popup(@[
        @"Centre", @"Left", @"Right",
        @"Top centre", @"Top left", @"Top right",
    ]);
    [alignPopup selectItemAtIndex:cfg_display_text_alignment.get_value()];
    [alignPopup setTarget:self];
    [alignPopup setAction:@selector(onAlignment:)];

    // Scroll type
    NSPopUpButton* scrollPopup = make_popup(@[@"Automatic", @"Manual"]);
    [scrollPopup selectItemAtIndex:cfg_display_scroll_type.get_value()];
    [scrollPopup setTarget:self];
    [scrollPopup setAction:@selector(onScrollType:)];

    // Continuous scrolling
    NSButton* continuousCheck = make_checkbox(@"Continuous scrolling (ignores scroll time)");
    continuousCheck.state = cfg_display_scroll_continuous.get_value()
                                ? NSControlStateValueOn : NSControlStateValueOff;
    [continuousCheck setTarget:self];
    [continuousCheck setAction:@selector(onContinuous:)];

    // Scroll time (ms)
    NSTextField* scrollTimeField = make_field(@"milliseconds");
    scrollTimeField.stringValue = [NSString stringWithFormat:@"%d",
                                   (int)cfg_display_scroll_time.get_value()];
    scrollTimeField.target = self;
    scrollTimeField.action = @selector(onScrollTime:);

    // Fade time (ms)
    NSTextField* fadeTimeField = make_field(@"milliseconds");
    fadeTimeField.stringValue = [NSString stringWithFormat:@"%d",
                                 (int)cfg_display_highlight_fade_time.get_value()];
    fadeTimeField.target = self;
    fadeTimeField.action = @selector(onFadeTime:);

    // Line gap
    NSTextField* linegapField = make_field(@"pixels");
    linegapField.stringValue = [NSString stringWithFormat:@"%d",
                                (int)cfg_display_linegap.get_value()];
    linegapField.target = self;
    linegapField.action = @selector(onLinegap:);

    // Custom foreground: toggle + colour well on same row
    NSButton* customFgCheck = make_checkbox(@"Custom text colour:");
    customFgCheck.state = cfg_display_custom_fg_colour.get_value()
                              ? NSControlStateValueOn : NSControlStateValueOff;
    [customFgCheck setTarget:self];
    [customFgCheck setAction:@selector(onCustomFg:)];

    NSColorWell* fgWell = make_colorwell((uint32_t)cfg_display_fg_colour.get_value(),
                                         self, @selector(onFgColour:));

    NSStackView* fgRow = [NSStackView stackViewWithViews:@[customFgCheck, fgWell]];
    fgRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fgRow.spacing = 8;

    // Custom highlight: toggle + colour well
    NSButton* customHlCheck = make_checkbox(@"Custom highlight colour:");
    customHlCheck.state = cfg_display_custom_hl_colour.get_value()
                              ? NSControlStateValueOn : NSControlStateValueOff;
    [customHlCheck setTarget:self];
    [customHlCheck setAction:@selector(onCustomHl:)];

    NSColorWell* hlWell = make_colorwell((uint32_t)cfg_display_hl_colour.get_value(),
                                         self, @selector(onHlColour:));

    NSStackView* hlRow = [NSStackView stackViewWithViews:@[customHlCheck, hlWell]];
    hlRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    hlRow.spacing = 8;

    // Past text colour type
    NSPopUpButton* pastTypePopup = make_popup(@[
        @"Blend with background",  // BlendBackground = 0
        @"Same as text",           // SameAsMainText  = 1
        @"Custom",                 // Custom          = 2
        @"Same as highlight",      // SameAsHighlight = 3
    ]);
    [pastTypePopup selectItemAtIndex:cfg_display_pasttext_colour_type.get_value()];
    [pastTypePopup setTarget:self];
    [pastTypePopup setAction:@selector(onPastType:)];

    // Past text custom colour well
    NSColorWell* pastWell = make_colorwell((uint32_t)cfg_display_pasttext_colour.get_value(),
                                            self, @selector(onPastColour:));

    // Custom font toggle
    NSButton* customFontCheck = make_checkbox(@"Use custom font (not yet configurable on macOS)");
    customFontCheck.state = cfg_display_custom_font.get_value()
                                ? NSControlStateValueOn : NSControlStateValueOff;
    [customFontCheck setTarget:self];
    [customFontCheck setAction:@selector(onCustomFont:)];

    NSStackView* stack = make_form(@[
        make_row(@"Text alignment:", alignPopup),
        make_row(@"Scroll type:", scrollPopup),
        continuousCheck,
        make_row(@"Scroll time (ms):", scrollTimeField),
        make_row(@"Highlight fade (ms):", fadeTimeField),
        make_row(@"Line gap (px):", linegapField),
        fgRow,
        hlRow,
        make_row(@"Past text colour:", pastTypePopup),
        make_row(@"Past text (custom):", pastWell),
        customFontCheck,
    ]);
    stack.frame = NSMakeRect(0, 0, 540, 420);
    self.view = stack;
}

- (void)onAlignment:(NSPopUpButton*)sender
{
    cfg_display_text_alignment = (int)sender.indexOfSelectedItem;
    repaint_all_lyric_panels();
}

- (void)onScrollType:(NSPopUpButton*)sender
{
    cfg_display_scroll_type = (int)sender.indexOfSelectedItem;
}

- (void)onContinuous:(NSButton*)sender
{
    cfg_display_scroll_continuous = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

- (void)onScrollTime:(NSTextField*)sender
{
    int v = [sender.stringValue intValue];
    if(v >= 0 && v <= 2000) cfg_display_scroll_time = v;
}

- (void)onFadeTime:(NSTextField*)sender
{
    int v = [sender.stringValue intValue];
    if(v >= 0 && v <= 1000) cfg_display_highlight_fade_time = v;
}

- (void)onLinegap:(NSTextField*)sender
{
    int v = [sender.stringValue intValue];
    if(v >= 0 && v <= 50) cfg_display_linegap = v;
}

- (void)onCustomFg:(NSButton*)sender
{
    cfg_display_custom_fg_colour = (sender.state == NSControlStateValueOn) ? 1 : 0;
    repaint_all_lyric_panels();
}

- (void)onFgColour:(NSColorWell*)sender
{
    cfg_display_fg_colour = (int)colorref_from_nscolor(sender.color);
    repaint_all_lyric_panels();
}

- (void)onCustomHl:(NSButton*)sender
{
    cfg_display_custom_hl_colour = (sender.state == NSControlStateValueOn) ? 1 : 0;
    repaint_all_lyric_panels();
}

- (void)onHlColour:(NSColorWell*)sender
{
    cfg_display_hl_colour = (int)colorref_from_nscolor(sender.color);
    repaint_all_lyric_panels();
}

- (void)onPastType:(NSPopUpButton*)sender
{
    cfg_display_pasttext_colour_type = (int)sender.indexOfSelectedItem;
    repaint_all_lyric_panels();
}

- (void)onPastColour:(NSColorWell*)sender
{
    cfg_display_pasttext_colour = (int)colorref_from_nscolor(sender.color);
    repaint_all_lyric_panels();
}

- (void)onCustomFont:(NSButton*)sender
{
    cfg_display_custom_font = (sender.state == NSControlStateValueOn) ? 1 : 0;
}

@end

// ---------------------------------------------------------------------------
// Upload page
// ---------------------------------------------------------------------------

@interface OpenLyricsPrefsUploadVC : NSViewController
@end

@implementation OpenLyricsPrefsUploadVC

- (instancetype)init { self = [super initWithNibName:nil bundle:nil]; return self; }

- (void)loadView
{
    NSPopUpButton* stratPopup = make_popup(@[@"Never", @"After manual edit"]);
    int stratVal = (int)cfg_upload_strategy.get_value();
    [stratPopup selectItemAtIndex:stratVal == static_cast<int>(UploadStrategy::OnEdit) ? 1 : 0];
    [stratPopup setTarget:self];
    [stratPopup setAction:@selector(onStrategy:)];

    NSStackView* stack = make_form(@[
        make_row(@"Upload to LRClib:", stratPopup),
    ]);
    stack.frame = NSMakeRect(0, 0, 480, 80);
    self.view = stack;
}

- (void)onStrategy:(NSPopUpButton*)sender
{
    cfg_upload_strategy = sender.indexOfSelectedItem == 1
                              ? static_cast<int>(UploadStrategy::OnEdit)
                              : static_cast<int>(UploadStrategy::Never);
}

@end

// ===========================================================================
// preferences_page subclasses + factory registrations
// ===========================================================================

namespace
{

class PrefsPageRoot : public preferences_page
{
public:
    service_ptr instantiate() override
    {
        return fb2k::wrapNSObject([OpenLyricsPrefsRootVC new]);
    }
    const char* get_name() override { return "OpenLyrics"; }
    GUID get_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
    GUID get_parent_guid() override { return guid_tools; }
};
FB2K_SERVICE_FACTORY(PrefsPageRoot)

class PrefsPageSearching : public preferences_page
{
public:
    service_ptr instantiate() override
    {
        return fb2k::wrapNSObject([OpenLyricsPrefsSearchVC new]);
    }
    const char* get_name() override { return "Searching"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SEARCHING; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageSearching)

class PrefsPageSaving : public preferences_page
{
public:
    service_ptr instantiate() override
    {
        return fb2k::wrapNSObject([OpenLyricsPrefsSavingVC new]);
    }
    const char* get_name() override { return "Saving"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SAVING; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageSaving)

class PrefsPageBackground : public preferences_page
{
public:
    service_ptr instantiate() override { return fb2k::wrapNSObject([OpenLyricsPrefsBackgroundVC new]); }
    const char* get_name() override { return "Background"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_BACKGROUND; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageBackground)

class PrefsPageEdit : public preferences_page
{
public:
    service_ptr instantiate() override { return fb2k::wrapNSObject([OpenLyricsPrefsEditVC new]); }
    const char* get_name() override { return "Editing"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_EDIT; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageEdit)

class PrefsPageSearchSources : public preferences_page
{
public:
    service_ptr instantiate() override { return fb2k::wrapNSObject([OpenLyricsPrefsSearchSourcesVC new]); }
    const char* get_name() override { return "Search sources"; }
    GUID get_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageSearchSources)

class PrefsPageLocalFiles : public preferences_page
{
public:
    service_ptr instantiate() override { return fb2k::wrapNSObject([OpenLyricsPrefsLocalFilesVC new]); }
    const char* get_name() override { return "Local files"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SRC_LOCALFILES; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
};
FB2K_SERVICE_FACTORY(PrefsPageLocalFiles)

class PrefsPageMetaTags : public preferences_page
{
public:
    service_ptr instantiate() override { return fb2k::wrapNSObject([OpenLyricsPrefsMetaTagsVC new]); }
    const char* get_name() override { return "Metadata tags"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SRC_METATAGS; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
};
FB2K_SERVICE_FACTORY(PrefsPageMetaTags)

class PrefsPageMusixmatch : public preferences_page
{
public:
    service_ptr instantiate() override { return fb2k::wrapNSObject([OpenLyricsPrefsMusixmatchVC new]); }
    const char* get_name() override { return "Musixmatch"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_SRC_MUSIXMATCH; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_SEARCH_SOURCES; }
};
FB2K_SERVICE_FACTORY(PrefsPageMusixmatch)

class PrefsPageDisplay : public preferences_page
{
public:
    service_ptr instantiate() override
    {
        return fb2k::wrapNSObject([OpenLyricsPrefsDisplayVC new]);
    }
    const char* get_name() override { return "Display"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_DISPLAY; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageDisplay)

class PrefsPageUpload : public preferences_page
{
public:
    service_ptr instantiate() override
    {
        return fb2k::wrapNSObject([OpenLyricsPrefsUploadVC new]);
    }
    const char* get_name() override { return "Uploading"; }
    GUID get_guid() override { return GUID_PREFS_PAGE_UPLOAD; }
    GUID get_parent_guid() override { return GUID_PREFERENCES_PAGE_ROOT; }
};
FB2K_SERVICE_FACTORY(PrefsPageUpload)

} // namespace
