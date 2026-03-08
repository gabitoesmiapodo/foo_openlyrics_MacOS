// MacStubs.mm
// Stub implementations of Windows-only / UI-panel symbols needed by the shared
// src/ files.  Real implementations will be provided as the macOS port matures.
#include "stdafx.h"

#include "../src/ui_hooks.h"

// ---------------------------------------------------------------------------
// UI panel hooks
// ---------------------------------------------------------------------------

// num_visible_lyric_panels, repaint_all_lyric_panels, and announce_lyric_update
// are implemented in OpenLyricsView.mm.

// recompute_lyric_panel_backgrounds() is implemented in OpenLyricsView.mm.

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
// Lyric editor / manual search (macOS stubs — Task 7.1 / Task 8.1)
// ---------------------------------------------------------------------------
// SpawnLyricEditorMac is implemented in OpenLyricsEditor.mm.
// SpawnManualSearchMac is implemented in OpenLyricsManualSearch.mm.

// preferences::*, defaultui::*, and GUID_PREFERENCES_PAGE_* are implemented
// in OpenLyricsPreferences.mm (Task 9.1).
