// ContextMenuTestStubs.mm
// Minimal stubs for symbols referenced by OpenLyricsView's context menu actions,
// needed only by the test target. The main component target uses the real
// implementations from lyric_search.cpp, tag_util.cpp, and MacStubs.mm.

#include "stdafx.h"
#include "../src/lyric_search.h"
#include "../src/tag_util.h"
#include "../src/ui_hooks.h"

// ---------------------------------------------------------------------------
// MacStubs equivalents for the test target
// ---------------------------------------------------------------------------

void SpawnLyricEditorMac() {}
void SpawnManualSearchMac() {}
void SpawnExternalLyricWindow() {}
void recompute_lyric_panel_backgrounds() {}
void announce_lyric_search_avoided(metadb_handle_ptr /*track*/, SearchAvoidanceReason /*reason*/) {}

// ---------------------------------------------------------------------------
// lyric_search.h
// ---------------------------------------------------------------------------

void initiate_lyrics_autosearch(metadb_handle_ptr /*track*/,
                                metadb_v2_rec_t /*track_info*/,
                                bool /*ignore_search_avoidance*/) {}

// ---------------------------------------------------------------------------
// tag_util.h
// ---------------------------------------------------------------------------

metadb_v2_rec_t get_full_metadata(metadb_handle_ptr /*track*/)
{
    return {};
}
