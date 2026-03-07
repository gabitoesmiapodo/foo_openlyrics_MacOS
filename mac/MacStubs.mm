// MacStubs.mm
// Stub implementations of Windows-only / UI-panel symbols needed by the shared
// src/ files.  Real implementations will be provided as the macOS port matures.
#include "stdafx.h"

#include "../src/ui_hooks.h"
#include "../src/preferences.h"

// ---------------------------------------------------------------------------
// UI panel hooks
// ---------------------------------------------------------------------------

size_t num_visible_lyric_panels()
{
    return 0;
}

void repaint_all_lyric_panels()
{
}

void recompute_lyric_panel_backgrounds()
{
}

void announce_lyric_update(LyricUpdate /*update*/)
{
}

void announce_lyric_search_avoided(metadb_handle_ptr /*track*/, SearchAvoidanceReason /*reason*/)
{
}

// ---------------------------------------------------------------------------
// External window
// ---------------------------------------------------------------------------

void SpawnExternalLyricWindow()
{
}

// ---------------------------------------------------------------------------
// preferences::searching
// ---------------------------------------------------------------------------

namespace preferences
{
namespace searching
{
    uint64_t source_config_generation()
    {
        return 0;
    }

    std::vector<GUID> active_sources()
    {
        return {};
    }

    bool exclude_trailing_brackets()
    {
        return false;
    }

    const pfc::string8& skip_filter()
    {
        static pfc::string8 s;
        return s;
    }

    LyricType preferred_lyric_type()
    {
        return LyricType::Synced;
    }

    bool should_search_without_panels()
    {
        return false;
    }

    std::vector<std::string> tags()
    {
        return {};
    }

    std::string_view musixmatch_api_key()
    {
        return {};
    }

    namespace raw
    {
        std::vector<GUID> active_sources_configured()
        {
            return {};
        }

        bool is_skip_filter_default()
        {
            return true;
        }
    }
}

// ---------------------------------------------------------------------------
// preferences::editing
// ---------------------------------------------------------------------------

namespace editing
{
    std::vector<AutoEditType> automated_auto_edits()
    {
        return {};
    }
}

// ---------------------------------------------------------------------------
// preferences::saving
// ---------------------------------------------------------------------------

namespace saving
{
    AutoSaveStrategy autosave_strategy()
    {
        return AutoSaveStrategy::Never;
    }

    GUID save_source()
    {
        return {};
    }

    std::string filename(metadb_handle_ptr /*track*/, const metadb_v2_rec_t& /*track_info*/)
    {
        return {};
    }

    std::string_view untimed_tag()
    {
        return "LYRICS";
    }

    std::string_view timestamped_tag()
    {
        return "SYNCEDLYRICS";
    }

    bool merge_equivalent_lrc_lines()
    {
        return false;
    }

    namespace raw
    {
        SaveDirectoryClass directory_class()
        {
            return SaveDirectoryClass::TrackFileDirectory;
        }
    }
}

// ---------------------------------------------------------------------------
// preferences::display
// ---------------------------------------------------------------------------

namespace display
{
    t_ui_font font()
    {
        return nullptr;
    }

    t_ui_color main_text_colour()
    {
        return 0x00FFFFFF; // white
    }

    t_ui_color highlight_colour()
    {
        return 0x0000BFFF; // deep sky blue
    }

    t_ui_color past_text_colour()
    {
        return 0x00808080; // grey
    }

    LineScrollType scroll_type()
    {
        return LineScrollType::Automatic;
    }

    double scroll_time_seconds()
    {
        return 0.5;
    }

    TextAlignment text_alignment()
    {
        return TextAlignment::MidCentre;
    }

    double highlight_fade_seconds()
    {
        return 0.25;
    }

    int linegap()
    {
        return 4;
    }

    bool debug_logs_enabled()
    {
        return false;
    }

    namespace raw
    {
        bool font_is_custom()
        {
            return false;
        }
    }
}

// ---------------------------------------------------------------------------
// preferences::background
// ---------------------------------------------------------------------------

namespace background
{
    BackgroundFillType fill_type()
    {
        return BackgroundFillType::Default;
    }

    BackgroundImageType image_type()
    {
        return BackgroundImageType::None;
    }

    t_ui_color colour()
    {
        return 0x00000000;
    }

    t_ui_color gradient_tl()
    {
        return 0x00000000;
    }

    t_ui_color gradient_tr()
    {
        return 0x00000000;
    }

    t_ui_color gradient_bl()
    {
        return 0x00000000;
    }

    t_ui_color gradient_br()
    {
        return 0x00000000;
    }

    bool maintain_img_aspect_ratio()
    {
        return true;
    }

    double image_opacity()
    {
        return 1.0;
    }

    int blur_radius()
    {
        return 0;
    }

    std::string custom_image_path()
    {
        return {};
    }

    bool external_window_opaque()
    {
        return true;
    }
}

// ---------------------------------------------------------------------------
// preferences::upload
// ---------------------------------------------------------------------------

namespace upload
{
    UploadStrategy lrclib_upload_strategy()
    {
        return UploadStrategy::Never;
    }
}

} // namespace preferences

// ---------------------------------------------------------------------------
// defaultui stubs
// ---------------------------------------------------------------------------

namespace defaultui
{
    t_ui_font default_font()
    {
        return nullptr;
    }

    t_ui_font console_font()
    {
        return nullptr;
    }

    t_ui_color background_colour()
    {
        return 0x00000000;
    }

    t_ui_color text_colour()
    {
        return 0x00FFFFFF;
    }

    t_ui_color highlight_colour()
    {
        return 0x0000BFFF;
    }
}

// ---------------------------------------------------------------------------
// Preferences page GUIDs (referenced from shared headers)
// ---------------------------------------------------------------------------

const GUID GUID_PREFERENCES_PAGE_ROOT = {};
const GUID GUID_PREFERENCES_PAGE_SEARCH_SOURCES = {};
