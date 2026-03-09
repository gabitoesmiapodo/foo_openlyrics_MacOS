#include "stdafx.h"

#include "cJSON.h"

#include "logging.h"
#include "lyric_data.h"
#include "lyric_source.h"
#include "tag_util.h"

static const GUID src_guid = { 0xaac13215, 0xe32e, 0x4667, { 0xac, 0xd7, 0x1f, 0xd, 0xbd, 0x84, 0x27, 0xe4 } };

class NetEaseLyricsSource : public LyricSourceRemote
{
    const GUID& id() const final
    {
        return src_guid;
    }
    std::tstring_view friendly_name() const final
    {
        return _T("NetEase Online Music");
    }

    std::vector<LyricDataRaw> search(const LyricSearchParams& params, abort_callback& abort) final;
    bool lookup(LyricDataRaw& data, abort_callback& abort) final;

private:
    std::vector<LyricDataRaw> parse_song_ids(cJSON* json);
};
static const LyricSourceFactory<NetEaseLyricsSource> src_factory;

static const char* BASE_URL = "https://music.163.com/api";

static const LyricSourceRemote::HttpHeaders g_netease_headers = {
    {"Referer", "https://music.163.com"},
    {"Cookie", "appver=2.0.2"},
    {"charset", "utf-8"},
    {"Content-Type", "application/x-www-form-urlencoded"},
    // Passing a Chinese IP range header causes NetEase to return more sensible results.
    {"X-Real-IP", "202.96.0.0"},
};

std::vector<LyricDataRaw> NetEaseLyricsSource::parse_song_ids(cJSON* json)
{
    if((json == nullptr) || (json->type != cJSON_Object))
    {
        LOG_INFO("Root object is null or not an object");
        return {};
    }

    cJSON* result_obj = cJSON_GetObjectItem(json, "result");
    if((result_obj == nullptr) || (result_obj->type != cJSON_Object))
    {
        LOG_INFO("No valid 'result' property available");
        return {};
    }
    cJSON* song_arr = cJSON_GetObjectItem(result_obj, "songs");
    if((song_arr == nullptr) || (song_arr->type != cJSON_Array))
    {
        LOG_INFO("No valid 'songs' property available");
        return {};
    }

    int song_arr_len = cJSON_GetArraySize(song_arr);
    if(song_arr_len <= 0)
    {
        LOG_INFO("Songs array has no items available");
        return {};
    }

    std::vector<LyricDataRaw> output;
    for(int song_index = 0; song_index < song_arr_len; song_index++)
    {
        cJSON* song_item = cJSON_GetArrayItem(song_arr, song_index);
        if((song_item == nullptr) || (song_item->type != cJSON_Object))
        {
            LOG_INFO("Song array entry %d not available or invalid", song_index);
            continue;
        }

        const char* result_artist = nullptr;
        const char* result_album = nullptr;
        const char* result_title = nullptr;
        std::optional<int> result_duration_sec = {};

        cJSON* artist_list_item = cJSON_GetObjectItem(song_item, "artists");
        if((artist_list_item != nullptr) && (artist_list_item->type == cJSON_Array))
        {
            int artist_list_len = cJSON_GetArraySize(artist_list_item);
            if(artist_list_len > 0)
            {
                cJSON* artist_item = cJSON_GetArrayItem(artist_list_item, 0);
                if((artist_item != nullptr) && (artist_item->type == cJSON_Object))
                {
                    cJSON* artist_name = cJSON_GetObjectItem(artist_item, "name");
                    if((artist_name != nullptr) && (artist_name->type == cJSON_String))
                    {
                        result_artist = artist_name->valuestring;
                    }
                }
            }
        }

        cJSON* album_item = cJSON_GetObjectItem(song_item, "album");
        if((album_item != nullptr) && (album_item->type == cJSON_Object))
        {
            cJSON* album_title_item = cJSON_GetObjectItem(album_item, "name");
            if((album_title_item != nullptr) && (album_title_item->type == cJSON_String))
            {
                result_album = album_title_item->valuestring;
            }
        }

        cJSON* title_item = cJSON_GetObjectItem(song_item, "name");
        if((title_item != nullptr) && (title_item->type == cJSON_String))
        {
            result_title = title_item->valuestring;
        }

        cJSON* song_id_item = cJSON_GetObjectItem(song_item, "id");
        if((song_id_item == nullptr) || (song_id_item->type != cJSON_Number))
        {
            LOG_INFO("Song item ID field is not available or invalid");
            continue;
        }

        cJSON* duration_item = cJSON_GetObjectItem(song_item, "duration");
        if((duration_item != nullptr) && (duration_item->type == cJSON_Number))
        {
            result_duration_sec = duration_item->valueint / 1000; // Given duration is in milliseconds
        }

        LyricDataRaw data = {};
        data.source_id = src_guid;
        if(result_artist != nullptr) data.artist = result_artist;
        if(result_album != nullptr) data.album = result_album;
        if(result_title != nullptr) data.title = result_title;
        data.lookup_id = std::to_string((int64_t)song_id_item->valuedouble);
        data.type = LyricType::Synced;
        data.duration_sec = result_duration_sec;
        output.push_back(std::move(data));
    }

    return output;
}

std::vector<LyricDataRaw> NetEaseLyricsSource::search(const LyricSearchParams& params, abort_callback& abort)
{
    const std::string url = std::string(BASE_URL) + "/search/get?s=" + urlencode(params.artist) + '+'
                            + urlencode(params.title) + "&type=1&offset=0&sub=false&limit=5";
    LOG_INFO("Querying for song ID from %s...", url.c_str());

    pfc::string8 content;
    if(!post_url(url, g_netease_headers, "", "", content, abort))
    {
        return {};
    }

    cJSON* json = cJSON_ParseWithLength(content.c_str(), content.get_length());
    std::vector<LyricDataRaw> song_ids = parse_song_ids(json);
    cJSON_Delete(json);

    return song_ids;
}

bool NetEaseLyricsSource::lookup(LyricDataRaw& data, abort_callback& abort)
{
    assert(data.source_id == id());
    if(data.lookup_id.empty())
    {
        return false;
    }

    std::string url = std::string(BASE_URL) + "/song/lyric?tv=-1&kv=-1&lv=-1&os=pc&id=" + data.lookup_id;
    data.source_path = url;
    LOG_INFO("Get NetEase lyrics for song ID %s from %s...", data.lookup_id.c_str(), url.c_str());

    pfc::string8 content;
    if(!post_url(url, g_netease_headers, "", "", content, abort))
    {
        return false;
    }

    bool success = false;
    cJSON* json = cJSON_ParseWithLength(content.c_str(), content.get_length());
    if((json != nullptr) && (json->type == cJSON_Object))
    {
        cJSON* lrc_item = cJSON_GetObjectItem(json, "lrc");
        if((lrc_item != nullptr) && (lrc_item->type == cJSON_Object))
        {
            cJSON* lrc_lyric = cJSON_GetObjectItem(lrc_item, "lyric");
            if((lrc_lyric != nullptr) && (lrc_lyric->type == cJSON_String))
            {
                const std::string_view trimmed_text = trim_surrounding_whitespace(lrc_lyric->valuestring);
                data.text_bytes = string_to_raw_bytes(trimmed_text);
                success = true;
            }
        }
    }
    cJSON_Delete(json);

    return success;
}
