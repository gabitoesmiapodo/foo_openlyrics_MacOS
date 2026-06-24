#include "stdafx.h"
#include <cctype>

#include "logging.h"
#include "mvtf/mvtf.h"
#include "preferences.h"
#include "tag_util.h"

static std::string_view trim_surrounding(std::string_view str, std::string_view trimset)
{
    size_t first_non_trimset = str.find_first_not_of(trimset);
    size_t last_non_trimset = str.find_last_not_of(trimset);

    if(first_non_trimset == std::string_view::npos)
    {
        return "";
    }
    size_t len = (last_non_trimset + 1) - first_non_trimset;
    return str.substr(first_non_trimset, len);
}

std::string_view trim_surrounding_whitespace(std::string_view str)
{
    return trim_surrounding(str, "\r\n ");
}

std::string_view trim_surrounding_line_endings(std::string_view str)
{
    return trim_surrounding(str, "\r\n");
}

std::string_view trim_trailing_text_in_brackets(std::string_view str)
{
    std::string_view result = str;
    while(true)
    {
        size_t open_index = result.find_last_of("([{");
        if(open_index == std::string_view::npos)
        {
            break; // Nothing to trim
        }

        if(open_index == 0)
        {
            break; // Don't trim the entire string!
        }

        char opener = result[open_index];
        char closer = '\0';
        switch(opener)
        {
            case '[': closer = ']'; break;
            case '(': closer = ')'; break;
            case '{': closer = '}'; break;
        }
        assert(closer != '\0');

        size_t close_index = result.find_first_of(closer, open_index);
        if(close_index == std::string_view::npos)
        {
            break; // Unmatched open-bracket
        }

        result = result.substr(0, open_index);
    }

    return result;
}

metadb_v2_rec_t get_full_metadata(metadb_handle_ptr track)
{
    // This is effectively a duplicate of `metadb_handle_ptr::query_v2_()` except that
    // we need to call get_*full*_info_ref(), not just get_browse_info_ref() so that we
    // always have data for non-standard tags like lyrics when running in fb2k pre-v2.
    // This function can be removed if we migrate to targetting FB2K SDK version 81 or higher.
#if FOOBAR2000_TARGET_VERSION >= 81
#ifdef __APPLE__
    return track->query_v2_();
#else
    return static_cast<const metadb_handle_v2*>(track)->query_v2();
#endif
#else
    metadb_handle_v2::ptr track_v2;
    if(track->cast(track_v2))
    {
        return track_v2->query_v2();
    }

    metadb_v2_rec_t result = {};
    try
    {
        result.info = track->get_full_info_ref(fb2k::mainAborter());
    }
    catch(pfc::exception ex)
    {
        LOG_INFO("Failed to retrieve metadata for track due to IO error: %s", ex.what());
    }
    catch(...)
    {
        LOG_INFO("Failed to retrieve metadata for track due to an unknown error");
    }
    return result;
#endif
}

int string_edit_distance(const std::string_view strA, const std::string_view strB)
{
    // 2-row levenshtein distance
    int row_count = static_cast<int>(strA.length());
    int row_len = static_cast<int>(strB.length());

    int* prev_row = new int[row_len + 1];
    int* cur_row = new int[row_len + 1];
    for(int i = 0; i < row_len + 1; i++)
    {
        prev_row[i] = i;
    }

    for(int row = 0; row < row_count; row++)
    {
        cur_row[0] = row + 1;
        for(int i = 0; i < row_len; i++)
        {
            int delete_cost = prev_row[i + 1] + 1;
            int insert_cost = cur_row[i] + 1;
            int subst_cost;

            int a_lower = std::tolower(static_cast<unsigned char>(strA[row]));
            int b_lower = std::tolower(static_cast<unsigned char>(strB[i]));
            if(a_lower == b_lower)
            {
                subst_cost = prev_row[i];
            }
            else
            {
                subst_cost = prev_row[i] + 1;
            }

            cur_row[i + 1] = std::min(std::min(delete_cost, insert_cost), subst_cost);
        }

        int* tmp = cur_row;
        cur_row = prev_row;
        prev_row = tmp;
    }

    int result = prev_row[row_len];
    delete[] prev_row;
    delete[] cur_row;
    return result;
}

static std::string normalise_tag_for_match(std::string_view s)
{
#ifdef __APPLE__
    // Many CJK tracks are tagged in Traditional Chinese locally while remote sources
    // (QQ Music, NetEase, ...) return Simplified Chinese. A byte-level edit distance treats
    // these as completely different strings, so fold both sides to a common (Simplified)
    // form first. This is a no-op for non-Traditional input (ASCII, kana, already-Simplified).
    return fold_for_tag_match(s);
#else
    return std::string(s);
#endif
}

// Returns true when `shorter` is a case-insensitive prefix of `longer` that ends on a word
// boundary. This lets a bare title match one carrying a trailing edition/version marker, e.g.
// "Beautiful World" vs "Beautiful World -2021 Remastered-", while still rejecting "Love" vs
// "Lover" (the prefix there is not followed by a separator).
static bool is_word_boundary_prefix(const std::string& shorter, const std::string& longer)
{
    if(shorter.empty() || shorter.size() >= longer.size())
    {
        return false;
    }
    for(size_t i = 0; i < shorter.size(); i++)
    {
        if(std::tolower(static_cast<unsigned char>(shorter[i]))
           != std::tolower(static_cast<unsigned char>(longer[i])))
        {
            return false;
        }
    }
    const unsigned char next = static_cast<unsigned char>(longer[shorter.size()]);
    return (std::isalnum(next) == 0);
}

bool tag_values_match(std::string_view tagA, std::string_view tagB)
{
    if(preferences::searching::exclude_trailing_brackets())
    {
        tagA = trim_surrounding_whitespace(trim_trailing_text_in_brackets(tagA));
        tagB = trim_surrounding_whitespace(trim_trailing_text_in_brackets(tagB));
    }

    const std::string a = normalise_tag_for_match(tagA);
    const std::string b = normalise_tag_for_match(tagB);

    // Allow a few edits plus a small length-proportional slack, so minor spacing/punctuation
    // differences and multi-byte UTF-8 inflation (one CJK glyph == 3 bytes) don't cause a
    // false reject. The base of 3 preserves the historical behaviour for short ASCII tags.
    const size_t max_len = std::max(a.size(), b.size());
    const int max_edit_distance = std::max(3, static_cast<int>(max_len / 8));
    if(string_edit_distance(a, b) <= max_edit_distance)
    {
        return true;
    }

    // Tolerate a trailing edition/version marker that only one side carries.
    const std::string& shorter = (a.size() <= b.size()) ? a : b;
    const std::string& longer = (a.size() <= b.size()) ? b : a;
    if((shorter.size() >= 4) && is_word_boundary_prefix(shorter, longer))
    {
        return true;
    }

    return false;
}

std::string track_metadata(const metadb_v2_rec_t& track, std::string_view key)
{
    if(track.info == nullptr)
    {
        return {};
    }

    const file_info& track_info = track.info->info();
    return track_metadata(track_info, key);
}

std::string track_metadata(const file_info& track_info, std::string_view key)
{
    size_t value_index = track_info.meta_find_ex(key.data(), key.length());
    if(value_index == pfc::infinite_size)
    {
        return "";
    }

    size_t value_count = track_info.meta_enum_value_count(value_index);
    if(value_count == 0)
    {
        return "";
    }

    // NOTE: Previously we would concatenate the strings from every value of this tag.
    //       The motivation for this was mostly "well why not".
    //       This causes problems though because for example some tracks will list several
    //       artists, one in each instance of the "artist" tag. The search then tries to find
    //       tracks matching "artistAartistBartistC", which it is very unlikely to find.
    //       Now instead it will just search for "artistA" and maybe some results will
    //       include artists B & C as well, but thats probably an easier thing for the web
    //       searches to deal with.
    //       For a bug report about this on GitHub, see https://github.com/jacquesh/foo_openlyrics/issues/38
    if(value_count > 1)
    {
        std::string err_msg;
        err_msg += "metadata tag ";
        err_msg += key;
        err_msg += " appears multiple times for ";
        const char* const err_tags[] = { "artist", "album", "title" };
        for(const char* err_tag : err_tags)
        {
            err_msg += "/";
            size_t err_index = track_info.meta_find(err_tag);
            if(err_index == pfc::infinite_size) continue;

            size_t err_tag_count = track_info.meta_enum_value_count(err_index);
            if(err_tag_count == 0) continue;

            const char* err_tag_value = track_info.meta_enum_value(err_index, 0);
            err_msg += err_tag_value;
        }
        err_msg += ". Only the first value will be used of: ";

        for(size_t i = 0; i < value_count; i++)
        {
            err_msg += "/";
            err_msg += track_info.meta_enum_value(value_index, i);
        }
        err_msg += ".";

        LOG_INFO("%s", err_msg.c_str());
    }

    return track_info.meta_enum_value(value_index, 0);
}

std::optional<int> track_duration_in_seconds(const metadb_v2_rec_t& track)
{
    if(track.info != nullptr)
    {
        double track_len = track.info->info().get_length();
        if(track_len > 1.0)
        {
            return int(track_len);
        }
    }
    return {};
}

bool track_is_remote(metadb_handle_ptr track)
{
#if FOOBAR2000_TARGET_VERSION >= 81
    t_filestats2 playstats = track->get_stats2_();
    const bool is_remote = playstats.is_remote();
    return is_remote;
#else
    playable_location_impl playloc = track->get_location();
    const char* playloc_str = playloc.get_path();

    const bool is_remote = std::string_view(playloc_str).find("http") == 0;
    return is_remote;
#endif
}

bool starts_with_ignore_case(std::string_view input, std::string_view prefix)
{
    if(input.length() < prefix.length())
    {
        return false;
    }

    for(size_t i = 0; i < prefix.length(); i++)
    {
        const char input_char = static_cast<char>(std::tolower(static_cast<unsigned char>(input[i])));
        const char prefix_char = static_cast<char>(std::tolower(static_cast<unsigned char>(prefix[i])));
        if(input_char != prefix_char)
        {
            return false;
        }
    }
    return true;
}

// ============
// Tests
// ============
#if MVTF_TESTS_ENABLED
MVTF_TEST(tagutil_startswithignorecase_ignores_case)
{
    ASSERT(starts_with_ignore_case("qweasd", "qWe"));
}

MVTF_TEST(tagutil_startswithignorecase_works_for_prefix_being_the_whole_string)
{
    ASSERT(starts_with_ignore_case("QwEaSd", "qweasd"));
}
#endif
