// mac/tests/ImageProcessingTests.mm
// XCTest unit tests for mac/ImageProcessing.mm
#import <XCTest/XCTest.h>
#include "stdafx.h"
#include "../src/img_processing.h"

@interface ImageProcessingTests : XCTestCase
@end

@implementation ImageProcessingTests

- (void)testGenerateSolidBackground
{
    RGBAColour colour = {255, 0, 0, 255};
    Image img = generate_background_colour(100, 100, colour);
    XCTAssertTrue(img.valid());
    XCTAssertEqual(img.width, 100);
    XCTAssertEqual(img.height, 100);
    XCTAssertEqual(img.pixels[0], 255);
    XCTAssertEqual(img.pixels[1], 0);
    XCTAssertEqual(img.pixels[2], 0);
}

- (void)testGenerateGradientBackground
{
    RGBAColour tl = {255, 0, 0, 255};
    RGBAColour tr = {0, 255, 0, 255};
    RGBAColour bl = {0, 0, 255, 255};
    RGBAColour br = {255, 255, 0, 255};
    Image img = generate_background_colour(100, 100, tl, tr, bl, br);
    XCTAssertTrue(img.valid());
    XCTAssertEqual(img.width, 100);
    XCTAssertEqual(img.height, 100);
    // Top-left pixel should be close to red
    XCTAssertGreaterThan(img.pixels[0], (uint8_t)200);
}

- (void)testResizeImage
{
    RGBAColour colour = {128, 128, 128, 255};
    Image img = generate_background_colour(200, 200, colour);
    Image resized = resize_image(img, 100, 100);
    XCTAssertTrue(resized.valid());
    XCTAssertEqual(resized.width, 100);
    XCTAssertEqual(resized.height, 100);
}

- (void)testBlurImage
{
    RGBAColour colour = {128, 128, 128, 255};
    Image img = generate_background_colour(200, 200, colour);
    Image blurred = blur_image(img, 5);
    XCTAssertTrue(blurred.valid());
    XCTAssertEqual(blurred.width, 200);
    XCTAssertEqual(blurred.height, 200);
}

- (void)testTransposeImage
{
    Image img = generate_background_colour(100, 50, {1, 2, 3, 255});
    Image transposed = transpose_image(img);
    XCTAssertTrue(transposed.valid());
    XCTAssertEqual(transposed.width, 50);
    XCTAssertEqual(transposed.height, 100);
}

- (void)testLerpColour
{
    RGBAColour black = {0, 0, 0, 255};
    RGBAColour white = {255, 255, 255, 255};
    RGBAColour mid = lerp_colour(black, white, 128);
    XCTAssertGreaterThan(mid.r, (uint8_t)100);
    XCTAssertLessThan(mid.r, (uint8_t)200);
}

- (void)testLerpImage
{
    Image a = generate_background_colour(50, 50, {0, 0, 0, 255});
    Image b = generate_background_colour(50, 50, {200, 200, 200, 255});
    Image lerped = lerp_image(a, b, 0.5);
    XCTAssertTrue(lerped.valid());
    XCTAssertEqual(lerped.width, 50);
    XCTAssertEqual(lerped.height, 50);
    XCTAssertGreaterThan(lerped.pixels[0], (uint8_t)50);
    XCTAssertLessThan(lerped.pixels[0], (uint8_t)200);
}

- (void)testImageMoveSemantics
{
    Image a = generate_background_colour(10, 10, {1, 2, 3, 255});
    XCTAssertTrue(a.valid());
    Image b = std::move(a);
    XCTAssertTrue(b.valid());
    XCTAssertFalse(a.valid());
    XCTAssertEqual(b.width, 10);
    XCTAssertEqual(b.height, 10);
}

@end
