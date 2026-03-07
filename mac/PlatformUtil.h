#pragma once

#include <string>
#include <string_view>
#include <cstdint>
#include <vector>

// Win32 type shims
using COLORREF = uint32_t;
using TCHAR = char;
using UINT = unsigned int;
#ifndef __OBJC__
using BOOL = int;
#endif
using BYTE = uint8_t;
using DWORD = unsigned long;
using HRESULT = long;
using UINT_PTR = uintptr_t;
using WPARAM = uintptr_t;
using LPARAM = intptr_t;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

struct CPoint {
    int x = 0;
    int y = 0;
    CPoint() = default;
    CPoint(int x_, int y_) : x(x_), y(y_) {}
};

struct CSize {
    int cx = 0;
    int cy = 0;
    CSize() = default;
    CSize(int cx_, int cy_) : cx(cx_), cy(cy_) {}
};

struct CRect {
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
    CRect() = default;
    CRect(int l, int t, int r, int b) : left(l), top(t), right(r), bottom(b) {}
    int Width() const { return right - left; }
    int Height() const { return bottom - top; }
};

// On macOS, TCHAR is char -- no wide strings
namespace std {
    using tstring = string;
    using tstring_view = string_view;
}

// _T() macro: on Windows expands to wide-string literal, on macOS TCHAR==char so it's a no-op
#ifndef _T
#define _T(x) x
#endif

// TCHAR ctype helpers: on Windows these operate on TCHAR (potentially wide),
// on macOS TCHAR==char so map to the standard narrow-char functions.
#ifndef _istlower
#define _istlower(c) std::islower(static_cast<unsigned char>(c))
#endif
#ifndef _istupper
#define _istupper(c) std::isupper(static_cast<unsigned char>(c))
#endif
#ifndef _totupper
#define _totupper(c) static_cast<char>(std::toupper(static_cast<unsigned char>(c)))
#endif
#ifndef _totlower
#define _totlower(c) static_cast<char>(std::tolower(static_cast<unsigned char>(c)))
#endif

// Forward declarations so this header is self-contained for the LSP.
// The full definitions are provided by foobar2000+atl.h via stdafx.h.
namespace pfc { class stringLite; typedef stringLite string8; }

// String conversions (identity on macOS -- always UTF-8)
std::tstring to_tstring(std::string_view s);
std::tstring to_tstring(const std::string& s);
std::tstring to_tstring(const pfc::string8& s);

std::string from_tstring(std::tstring_view s);
std::string from_tstring(const std::tstring& s);

std::tstring normalise_utf8(std::tstring_view input);

bool is_char_whitespace(TCHAR c);
size_t find_first_whitespace(std::tstring_view str, size_t pos = 0);
size_t find_first_nonwhitespace(std::tstring_view str, size_t pos = 0);
size_t find_last_whitespace(std::tstring_view str, size_t pos = std::tstring_view::npos);
size_t find_last_nonwhitespace(std::tstring_view str, size_t pos = std::tstring_view::npos);

// COLORREF channel extraction (Windows COLORREF is 0x00BBGGRR)
inline uint8_t GetRValue(COLORREF c) { return (uint8_t)(c & 0xFF); }
inline uint8_t GetGValue(COLORREF c) { return (uint8_t)((c >> 8) & 0xFF); }
inline uint8_t GetBValue(COLORREF c) { return (uint8_t)((c >> 16) & 0xFF); }

// HRESULT stub (not used on macOS but shared headers reference HR_SUCCESS)
#define HR_SUCCESS(hr) hr_success(hr, __FILE__, __LINE__)
bool hr_success(HRESULT result, const char* filename, int line_number);
