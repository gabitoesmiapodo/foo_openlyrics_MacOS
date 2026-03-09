#import "stdafx.h"
#import "OpenLyricsView.h"
#include "../src/tag_util.h"

DECLARE_COMPONENT_VERSION("OpenLyrics", "0.0.1",
    "foo_openlyrics\n\n"
    "Open-source lyrics retrieval and display for foobar2000 on macOS.\n"
    "Source: https://github.com/jacquesh/foo_openlyrics\n"
);

VALIDATE_COMPONENT_FILENAME("foo_openlyrics.component");

// MARK: - View Controller

@interface OpenLyricsViewController : NSViewController
@end

@implementation OpenLyricsViewController

- (void)loadView {
    self.view = [[[OpenLyricsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)] autorelease];
}

@end

// MARK: - foobar2000 UI Element Registration

namespace {

class ui_element_openlyrics_mac : public ui_element_mac {
public:
    service_ptr instantiate(service_ptr arg) override {
        OpenLyricsViewController *vc = [[OpenLyricsViewController alloc] init];
        return fb2k::wrapNSObject(vc);
    }

    bool match_name(const char *name) override {
        return strcmp(name, "openlyricsMacOS") == 0;
    }

    fb2k::stringRef get_name() override {
        return fb2k::makeString("openlyricsMacOS");
    }

    GUID get_guid() override {
        // Generated GUID for OpenLyrics Panel
        return { 0x3a7f2e91, 0xb4c5, 0x4d08, { 0xa2, 0x6b, 0x51, 0xe3, 0x9f, 0x0c, 0x7d, 0x84 } };
    }
};

FB2K_SERVICE_FACTORY(ui_element_openlyrics_mac);

// MARK: - Play Callback

class OpenLyricsPlayCallback : public play_callback_static {
public:
    unsigned get_flags() override {
        return flag_on_playback_stop | flag_on_playback_new_track;
    }

    void on_playback_new_track(metadb_handle_ptr track) override {
        // LyricAutosearchManager (src/lyric_search.cpp) self-registers as a play_callback
        // and handles search triggering. announce_lyric_update() is called when results
        // arrive. Here we set the now-playing track on all panels so the no-lyrics state
        // can show track info and so announce_lyric_search_avoided() can match panels.
        set_now_playing_track(track, get_full_metadata(track));
    }

    void on_playback_stop(play_control::t_stop_reason reason) override {
        if (reason == play_control::stop_reason_starting_another) return;
        clear_all_lyric_panels();
    }

    // Unused callbacks — satisfy the pure-virtual interface.
    void on_playback_starting(play_control::t_track_command, bool) override {}
    void on_playback_seek(double) override {}
    void on_playback_pause(bool) override {}
    void on_playback_edited(metadb_handle_ptr) override {}
    void on_playback_dynamic_info(const file_info&) override {}
    void on_playback_dynamic_info_track(const file_info&) override {}
    void on_playback_time(double) override {}
    void on_volume_change(float) override {}
};

static play_callback_static_factory_t<OpenLyricsPlayCallback> g_play_cb_factory;

} // anonymous namespace
