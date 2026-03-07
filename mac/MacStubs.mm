// MacStubs.mm
// Stub implementations of Windows-only / UI-panel symbols needed by the shared
// src/ files.  Real implementations will be provided as the macOS port matures.
#include "stdafx.h"

#include "../src/ui_hooks.h"
#include "../src/preferences.h"

// ---------------------------------------------------------------------------
// UI panel hooks
// ---------------------------------------------------------------------------

// num_visible_lyric_panels, repaint_all_lyric_panels, and announce_lyric_update
// are implemented in OpenLyricsView.mm.

void recompute_lyric_panel_backgrounds() // TODO(stub): implement in Task 10.2
{
}

void announce_lyric_search_avoided(metadb_handle_ptr /*track*/, SearchAvoidanceReason /*reason*/) // TODO(stub): implement in Task 4.1
{
}

// ---------------------------------------------------------------------------
// External window
// ---------------------------------------------------------------------------

void SpawnExternalLyricWindow() // TODO(stub): implement in Task 11.1
{
}

// ---------------------------------------------------------------------------
// preferences::searching
// ---------------------------------------------------------------------------

namespace preferences
{
namespace searching
{
    uint64_t source_config_generation() // TODO(stub): implement in Task 9.1
    {
        return 0;
    }

    std::vector<GUID> active_sources() // TODO(stub): implement in Task 9.1
    {
        return {};
    }

    bool exclude_trailing_brackets() // TODO(stub): implement in Task 9.1
    {
        return false;
    }

    const pfc::string8& skip_filter() // TODO(stub): implement in Task 9.1
    {
        static pfc::string8 s;
        return s;
    }

    LyricType preferred_lyric_type() // TODO(stub): implement in Task 9.1
    {
        return LyricType::Synced;
    }

    bool should_search_without_panels() // TODO(stub): implement in Task 9.1
    {
        return false;
    }

    std::vector<std::string> tags() // TODO(stub): implement in Task 9.1
    {
        return {};
    }

    std::string_view musixmatch_api_key() // TODO(stub): implement in Task 9.1
    {
        return {};
    }

    namespace raw
    {
        std::vector<GUID> active_sources_configured() // TODO(stub): implement in Task 9.1
        {
            return {};
        }

        bool is_skip_filter_default() // TODO(stub): implement in Task 9.1
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
    std::vector<AutoEditType> automated_auto_edits() // TODO(stub): implement in Task 9.1
    {
        return {};
    }
}

// ---------------------------------------------------------------------------
// preferences::saving
// ---------------------------------------------------------------------------

namespace saving
{
    AutoSaveStrategy autosave_strategy() // TODO(stub): implement in Task 9.1
    {
        return AutoSaveStrategy::Never;
    }

    GUID save_source() // TODO(stub): implement in Task 9.1
    {
        return {};
    }

    std::string filename(metadb_handle_ptr /*track*/, const metadb_v2_rec_t& /*track_info*/) // TODO(stub): implement in Task 9.1
    {
        return {};
    }

    std::string_view untimed_tag() // TODO(stub): implement in Task 9.1
    {
        return "LYRICS";
    }

    std::string_view timestamped_tag() // TODO(stub): implement in Task 9.1
    {
        return "SYNCEDLYRICS";
    }

    bool merge_equivalent_lrc_lines() // TODO(stub): implement in Task 9.1
    {
        return false;
    }

    namespace raw
    {
        SaveDirectoryClass directory_class() // TODO(stub): implement in Task 9.1
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
    t_ui_font font() // TODO(stub): implement in Task 9.1
    {
        return nullptr;
    }

    t_ui_color main_text_colour() // TODO(stub): implement in Task 9.1
    {
        return 0x00FFFFFF; // white
    }

    t_ui_color highlight_colour() // TODO(stub): implement in Task 9.1
    {
        return 0x0000BFFF; // deep sky blue
    }

    t_ui_color past_text_colour() // TODO(stub): implement in Task 9.1
    {
        return 0x00808080; // grey
    }

    LineScrollType scroll_type() // TODO(stub): implement in Task 9.1
    {
        return LineScrollType::Automatic;
    }

    double scroll_time_seconds() // TODO(stub): implement in Task 9.1
    {
        return 0.5;
    }

    TextAlignment text_alignment() // TODO(stub): implement in Task 9.1
    {
        return TextAlignment::MidCentre;
    }

    double highlight_fade_seconds() // TODO(stub): implement in Task 9.1
    {
        return 0.25;
    }

    int linegap() // TODO(stub): implement in Task 9.1
    {
        return 4;
    }

    bool debug_logs_enabled() // TODO(stub): implement in Task 9.1
    {
        return false;
    }

    namespace raw
    {
        bool font_is_custom() // TODO(stub): implement in Task 9.1
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
    BackgroundFillType fill_type() // TODO(stub): implement in Task 9.1
    {
        return BackgroundFillType::Default;
    }

    BackgroundImageType image_type() // TODO(stub): implement in Task 9.1
    {
        return BackgroundImageType::None;
    }

    t_ui_color colour() // TODO(stub): implement in Task 9.1
    {
        return 0x00000000;
    }

    t_ui_color gradient_tl() // TODO(stub): implement in Task 9.1
    {
        return 0x00000000;
    }

    t_ui_color gradient_tr() // TODO(stub): implement in Task 9.1
    {
        return 0x00000000;
    }

    t_ui_color gradient_bl() // TODO(stub): implement in Task 9.1
    {
        return 0x00000000;
    }

    t_ui_color gradient_br() // TODO(stub): implement in Task 9.1
    {
        return 0x00000000;
    }

    bool maintain_img_aspect_ratio() // TODO(stub): implement in Task 9.1
    {
        return true;
    }

    double image_opacity() // TODO(stub): implement in Task 9.1
    {
        return 1.0;
    }

    int blur_radius() // TODO(stub): implement in Task 9.1
    {
        return 0;
    }

    std::string custom_image_path() // TODO(stub): implement in Task 9.1
    {
        return {};
    }

    bool external_window_opaque() // TODO(stub): implement in Task 9.1
    {
        return true;
    }
}

// ---------------------------------------------------------------------------
// preferences::upload
// ---------------------------------------------------------------------------

namespace upload
{
    UploadStrategy lrclib_upload_strategy() // TODO(stub): implement in Task 9.1
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
    t_ui_font default_font() // TODO(stub): implement in Task 9.1
    {
        return nullptr;
    }

    t_ui_font console_font() // TODO(stub): implement in Task 9.1
    {
        return nullptr;
    }

    t_ui_color background_colour() // TODO(stub): implement in Task 9.1
    {
        return 0x00000000;
    }

    t_ui_color text_colour() // TODO(stub): implement in Task 9.1
    {
        return 0x00FFFFFF;
    }

    t_ui_color highlight_colour() // TODO(stub): implement in Task 9.1
    {
        return 0x0000BFFF;
    }
}

// ---------------------------------------------------------------------------
// Preferences page GUIDs (referenced from shared headers)
// ---------------------------------------------------------------------------

const GUID GUID_PREFERENCES_PAGE_ROOT = {};
const GUID GUID_PREFERENCES_PAGE_SEARCH_SOURCES = {};
