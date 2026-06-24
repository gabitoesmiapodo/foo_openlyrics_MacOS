#import <XCTest/XCTest.h>
// PlatformUtil.h will be included via mac/stdafx.h PCH
#include "tag_util.h"

@interface PlatformUtilTests : XCTestCase
@end

@implementation PlatformUtilTests

- (void)testCRectWidth {
    CRect r{10, 20, 110, 220};
    XCTAssertEqual(r.Width(), 100);
}

- (void)testCRectHeight {
    CRect r{10, 20, 110, 220};
    XCTAssertEqual(r.Height(), 200);
}

- (void)testToTstringFromStringView {
    std::string input = "hello";
    std::tstring result = to_tstring(std::string_view(input));
    XCTAssertEqual(result, "hello");
}

- (void)testFromTstringFromTstringView {
    std::tstring input = "world";
    std::string result = from_tstring(std::tstring_view(input));
    XCTAssertEqual(result, "world");
}

- (void)testIsCharWhitespaceSpace {
    XCTAssertTrue(is_char_whitespace(' '));
}

- (void)testIsCharWhitespaceTab {
    XCTAssertTrue(is_char_whitespace('\t'));
}

- (void)testIsCharWhitespaceNewline {
    XCTAssertTrue(is_char_whitespace('\n'));
}

- (void)testIsCharWhitespaceNonWhitespace {
    XCTAssertFalse(is_char_whitespace('a'));
    XCTAssertFalse(is_char_whitespace('1'));
}

- (void)testNormaliseUtf8ReturnsNonEmpty {
    std::tstring input = "caf\xC3\xA9"; // café in UTF-8
    std::tstring result = normalise_utf8(std::tstring_view(input));
    XCTAssertFalse(result.empty());
}

- (void)testGetRValue {
    COLORREF c = 0x00FF0000; // blue in COLORREF (BGRA), actually 0x00RRGGBB
    // GetRValue extracts the low byte (R channel)
    XCTAssertEqual(GetRValue(c), 0);
    XCTAssertEqual(GetGValue(c), 0);
    XCTAssertEqual(GetBValue(c), 0xFF);
}

- (void)testFindFirstWhitespace {
    std::tstring s = "hello world";
    XCTAssertEqual(find_first_whitespace(std::tstring_view(s)), (size_t)5);
}

- (void)testFindFirstNonWhitespace {
    std::tstring s = "   hello";
    XCTAssertEqual(find_first_nonwhitespace(std::tstring_view(s)), (size_t)3);
}

// --- Tag matching (search-result matching changes) ---

- (void)testFoldForTagMatchAsciiIsNoOp {
    XCTAssertEqual(fold_for_tag_match("Hello World"), std::string("Hello World"));
}

- (void)testFoldForTagMatchTraditionalEqualsSimplified {
    // Traditional and Simplified variants of the same word must fold to the same form.
    // Assert equality of the folded results rather than a hardcoded codepoint so the test
    // does not depend on the exact ICU output bytes, only that the transform unifies them.
    XCTAssertEqual(fold_for_tag_match("\xE6\x84\x9B"), fold_for_tag_match("\xE7\x88\xB1")); // 愛 / 爱
}

- (void)testTagValuesMatchIdentical {
    XCTAssertTrue(tag_values_match("Bohemian Rhapsody", "Bohemian Rhapsody"));
}

- (void)testTagValuesMatchTraditionalVsSimplified {
    // Traditional-tagged local track vs Simplified result from a CJK source (後窗 / 后窗).
    XCTAssertTrue(tag_values_match("\xE5\xBE\x8C\xE7\xAA\x97", "\xE5\x90\x8E\xE7\xAA\x97"));
}

- (void)testTagValuesMatchTrailingEditionMarker {
    // A bare title matches one carrying a trailing edition/version marker.
    XCTAssertTrue(tag_values_match("Beautiful World", "Beautiful World -2021 Remastered-"));
}

- (void)testTagValuesMatchRejectsUnrelated {
    XCTAssertFalse(tag_values_match("Yesterday", "Paranoid Android"));
}

- (void)testTagValuesMatchLongStringsAllowMoreEdits {
    // Length-proportional slack: on a 34-byte tag the threshold scales to max_len/8 == 4, so a
    // 4-substitution difference still matches. This guards the loosened CJK/long-title behaviour.
    std::string a(34, 'a');
    std::string b = a;
    b[0] = b[9] = b[18] = b[27] = 'b'; // 4 substitutions => edit distance 4
    XCTAssertTrue(tag_values_match(a, b));
}

- (void)testTagValuesMatchShortStringsKeepBaseThreshold {
    // The same magnitude of difference (4 edits) on short tags stays rejected, since short tags
    // keep the historical base threshold of 3 - the loosening must not match unrelated titles.
    XCTAssertFalse(tag_values_match(std::string(4, 'a'), std::string(4, 'b')));
}

- (void)testTagValuesMatchRejectsMidGlyphPrefix {
    // A prefix that ends in the middle of a multi-byte UTF-8 glyph is not a real word boundary,
    // so it must not be accepted as a trailing-edition-marker match. "abcd\xC3" stops on the lead
    // byte of "é" (0xC3 0xA9); the byte after it in the longer string is a continuation byte.
    XCTAssertFalse(tag_values_match("abcd\xC3", "abcd\xC3\xA9 Extended Mix Version"));
}

@end
