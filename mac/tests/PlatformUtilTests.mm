#import <XCTest/XCTest.h>
// PlatformUtil.h will be included via mac/stdafx.h PCH

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

@end
