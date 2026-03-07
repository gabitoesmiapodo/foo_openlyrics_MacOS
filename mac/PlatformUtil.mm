#import "stdafx.h"
#import "PlatformUtil.h"
#import <Foundation/Foundation.h>

std::tstring to_tstring(std::string_view s) { return std::tstring(s); }
std::tstring to_tstring(const std::string& s) { return s; }
std::tstring to_tstring(const pfc::string8& s) { return std::tstring(s.ptr(), s.length()); }

std::string from_tstring(std::tstring_view s) { return std::string(s); }
std::string from_tstring(const std::tstring& s) { return s; }

std::tstring normalise_utf8(std::tstring_view input) {
    NSString *ns = [[NSString alloc] initWithBytes:input.data()
                                            length:input.size()
                                          encoding:NSUTF8StringEncoding];
    if (!ns) return std::tstring(input);
    NSString *normalised = [ns precomposedStringWithCanonicalMapping];
    const char *utf8 = [normalised UTF8String];
    if (!utf8) return std::tstring(input);
    return std::tstring(utf8, [normalised lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

bool is_char_whitespace(TCHAR c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

size_t find_first_whitespace(std::tstring_view str, size_t pos) {
    for (size_t i = pos; i < str.size(); i++) {
        if (is_char_whitespace(str[i])) return i;
    }
    return std::tstring_view::npos;
}

size_t find_first_nonwhitespace(std::tstring_view str, size_t pos) {
    for (size_t i = pos; i < str.size(); i++) {
        if (!is_char_whitespace(str[i])) return i;
    }
    return std::tstring_view::npos;
}

size_t find_last_whitespace(std::tstring_view str, size_t pos) {
    size_t start = (pos == std::tstring_view::npos) ? str.size() : pos + 1;
    for (size_t i = start; i > 0; i--) {
        if (is_char_whitespace(str[i - 1])) return i - 1;
    }
    return std::tstring_view::npos;
}

size_t find_last_nonwhitespace(std::tstring_view str, size_t pos) {
    size_t start = (pos == std::tstring_view::npos) ? str.size() : pos + 1;
    for (size_t i = start; i > 0; i--) {
        if (!is_char_whitespace(str[i - 1])) return i - 1;
    }
    return std::tstring_view::npos;
}

bool hr_success(HRESULT result, const char* filename, int line_number) {
    (void)filename;
    (void)line_number;
    return result >= 0;
}

// Stub for pfc::myassert -- called when PFC_DEBUG=1 but prebuilt SDK libs are Release.
// Defined here (rather than OpenLyricsRegistration.mm) so the test target, which does
// not link OpenLyricsRegistration.mm, also has it resolved.
namespace pfc {
    void myassert(const char* what, const char* file, unsigned line) {
        (void)what; (void)file; (void)line;
    }
}
