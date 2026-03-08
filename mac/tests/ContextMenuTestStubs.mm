// ContextMenuTestStubs.mm
// Minimal stubs for symbols referenced by OpenLyricsView's context menu actions
// and other panels (editor, manual search), needed only by the test target.
// The main component target uses the real implementations from the src/ files.

#include "stdafx.h"
#include "../src/lyric_io.h"
#include "../src/lyric_search.h"
#include "../src/tag_util.h"
#include "../src/ui_hooks.h"
#include "../src/sources/lyric_source.h"

// ---------------------------------------------------------------------------
// logging stub — prevents openlyrics_logging::printf from calling
// core_api::get_profile_path() (which dereferences the null g_foobar2000_api
// in XCTest processes that have no foobar2000 runtime).
// ---------------------------------------------------------------------------

#include "../src/logging.h"
#include <cstdarg>

namespace openlyrics_logging {
    void printf(Level /*lvl*/, const char* /*fmt*/, ...) {}
}

// ---------------------------------------------------------------------------
// MacStubs equivalents for the test target
// ---------------------------------------------------------------------------

// SpawnLyricEditorMac is implemented in OpenLyricsEditor.mm (linked by test target directly).
// SpawnManualSearchMac is implemented in OpenLyricsManualSearch.mm (linked by test target directly).
void SpawnExternalLyricWindow() {}
// recompute_lyric_panel_backgrounds(), announce_lyric_search_avoided(), and
// set_now_playing_track() are implemented in OpenLyricsView.mm (linked into test target).

// get_autosearch_progress_message lives in lyric_search.cpp (not in test target).
std::optional<std::string> get_autosearch_progress_message() { return std::nullopt; }

// ---------------------------------------------------------------------------
// Preference page GUIDs (defined in OpenLyricsPreferences.mm in main target)
// ---------------------------------------------------------------------------

#include "../src/preferences.h"

extern const GUID GUID_PREFERENCES_PAGE_ROOT = {
    0x29e96cfa, 0xab67, 0x4793, { 0xa1, 0xc3, 0xef, 0xc3, 0x0a, 0xbc, 0x8b, 0x74 }
};
extern const GUID GUID_PREFERENCES_PAGE_SEARCH_SOURCES = {
    0x73e2261d, 0x4a71, 0x427a, { 0x92, 0x57, 0xec, 0xaa, 0x17, 0xb9, 0xa8, 0xc8 }
};

// ---------------------------------------------------------------------------
// lyric_search.h
// ---------------------------------------------------------------------------

void initiate_lyrics_autosearch(metadb_handle_ptr /*track*/,
                                metadb_v2_rec_t /*track_info*/,
                                bool /*ignore_search_avoidance*/) {}

// get_full_metadata is provided by tag_util.cpp (linked into the test target).

// ---------------------------------------------------------------------------
// preferences stubs (subset needed by logging.cpp / lrc.cpp / tag_util.cpp)
// ---------------------------------------------------------------------------

namespace preferences
{
namespace display
{
    bool debug_logs_enabled()          { return false; }
    t_ui_color main_text_colour()      { return 0x00DCDCDC; } // RGB(220,220,220)
    t_ui_color highlight_colour()      { return 0x00FFBF00; } // RGB(0,191,255)
    t_ui_color past_text_colour()      { return 0x00808080; } // RGB(128,128,128)
    int        linegap()               { return 8; }
    TextAlignment text_alignment()     { return TextAlignment::MidCentre; }
    double scroll_time_seconds()       { return 0.5; }
}
namespace saving
{
    bool merge_equivalent_lrc_lines() { return false; }
    std::string_view untimed_tag()     { return "LYRICS"; }
    std::string_view timestamped_tag() { return "SYNCEDLYRICS"; }
}
namespace searching
{
    bool exclude_trailing_brackets() { return false; }
}
namespace background
{
    BackgroundFillType  fill_type()               { return BackgroundFillType::Default; }
    BackgroundImageType image_type()              { return BackgroundImageType::None; }
    t_ui_color          colour()                  { return 0x001A1A1A; }
    t_ui_color          gradient_tl()             { return 0x001A1A1A; }
    t_ui_color          gradient_tr()             { return 0x001A1A1A; }
    t_ui_color          gradient_bl()             { return 0x001A1A1A; }
    t_ui_color          gradient_br()             { return 0x001A1A1A; }
    bool                maintain_img_aspect_ratio() { return false; }
    double              image_opacity()           { return 1.0; }
    int                 blur_radius()             { return 0; }
    std::string         custom_image_path()       { return ""; }
    bool                external_window_opaque()  { return false; }
}
}

// ---------------------------------------------------------------------------
// LyricSearchHandle stubs
// Enough for the linker to resolve symbols when OpenLyricsManualSearch.mm is
// compiled into the test target. In test context core_api::are_services_available()
// returns false so the real search path is never exercised.
// ---------------------------------------------------------------------------

LyricSearchHandle::LyricSearchHandle(LyricUpdate::Type type,
                                     metadb_handle_ptr track,
                                     metadb_v2_rec_t track_info,
                                     abort_callback& abort)
    : m_track(track)
    , m_track_info(track_info)
    , m_type(type)
    , m_lyrics()
    , m_abort(abort)
    , m_status(Status::Complete)  // immediately complete — never used in tests
    , m_progress()
    , m_searched_remote_sources(false)
{
}

LyricSearchHandle::LyricSearchHandle(LyricSearchHandle&& other)
    : m_track(other.m_track)
    , m_type(other.m_type)
    , m_lyrics(std::move(other.m_lyrics))
    , m_abort(other.m_abort)
    , m_status(other.m_status)
    , m_progress(std::move(other.m_progress))
    , m_searched_remote_sources(other.m_searched_remote_sources)
{
    other.m_status = Status::Closed;
}

LyricSearchHandle::~LyricSearchHandle() {}

LyricUpdate::Type LyricSearchHandle::get_type()       { return m_type; }
std::string       LyricSearchHandle::get_progress()    { return m_progress; }

bool LyricSearchHandle::wait_for_complete(uint32_t /*timeout_ms*/) { return true; }

bool LyricSearchHandle::is_complete()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return (m_status == Status::Complete) || (m_status == Status::Closed);
}

bool LyricSearchHandle::has_result()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return !m_lyrics.empty();
}

bool LyricSearchHandle::has_searched_remote_sources()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_searched_remote_sources;
}

LyricData LyricSearchHandle::get_result()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    LyricData result = std::move(m_lyrics.front());
    m_lyrics.erase(m_lyrics.begin());
    return result;
}

abort_callback& LyricSearchHandle::get_checked_abort() { m_abort.check(); return m_abort; }
metadb_handle_ptr LyricSearchHandle::get_track()       { return m_track; }
const metadb_v2_rec_t& LyricSearchHandle::get_track_info() { return m_track_info; }

void LyricSearchHandle::set_started()               {}
void LyricSearchHandle::set_progress(std::string_view) {}
void LyricSearchHandle::set_remote_source_searched() {}
void LyricSearchHandle::set_result(LyricData&& data, bool /*final_result*/)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_lyrics.push_back(std::move(data));
}
void LyricSearchHandle::set_complete()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_status = Status::Complete;
    m_complete_cv.notify_all();
}

// ---------------------------------------------------------------------------
// io::search_for_all_lyrics stub
// ---------------------------------------------------------------------------

namespace io
{
    void search_for_all_lyrics(LyricSearchHandle& handle,
                               std::string /*artist*/,
                               std::string /*album*/,
                               std::string /*title*/)
    {
        // In test context this is never called (guarded by are_services_available).
        handle.set_complete();
    }

    void search_for_lyrics(LyricSearchHandle& handle, bool /*local_only*/)
    {
        handle.set_complete();
    }

    std::optional<LyricData> process_available_lyric_update(LyricUpdate /*update*/)
    {
        return std::nullopt;
    }

    bool save_lyrics(metadb_handle_ptr /*track*/,
                     const metadb_v2_rec_t& /*track_info*/,
                     LyricData& /*lyrics*/,
                     bool /*allow_overwrite*/)
    {
        return false;
    }

    bool delete_saved_lyrics(metadb_handle_ptr /*track*/, const LyricData& /*lyrics*/)
    {
        return false;
    }
}

// ---------------------------------------------------------------------------
// LyricSourceBase::get stub
// ---------------------------------------------------------------------------

LyricSourceBase* LyricSourceBase::get(GUID /*guid*/)
{
    return nullptr;
}

// ---------------------------------------------------------------------------
// lyric_metadata / metrics stubs (used by OpenLyricsBulkSearch.mm)
// ---------------------------------------------------------------------------

#include "../src/lyric_metadata.h"

void lyric_metadata_log_retrieved(const metadb_v2_rec_t& /*track_info*/,
                                   const LyricData& /*lyrics*/) {}

#include "../src/metrics.h"

namespace metrics
{
    void log_used_bulk_search() {}
    void log_used_external_window() {}
}
