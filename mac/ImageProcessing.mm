// mac/ImageProcessing.mm
// macOS implementation of img_processing.h.
// Platform-specific operations use Core Graphics and vImage.
// Pure pixel-math operations are direct ports of the Windows implementation.
#include "stdafx.h"

#import <Accelerate/Accelerate.h>

#include "../src/img_processing.h"
#include "../src/logging.h"

// ---------------------------------------------------------------------------
// Image class methods
// ---------------------------------------------------------------------------

Image::Image(Image&& other)
    : pixels(other.pixels)
    , width(other.width)
    , height(other.height)
{
    other.pixels = nullptr;
}

Image& Image::operator=(Image&& other)
{
    free(pixels);
    pixels = other.pixels;
    width = other.width;
    height = other.height;
    other.pixels = nullptr;
    return *this;
}

Image::~Image()
{
    free(pixels);
}

bool Image::valid() const
{
    return pixels != nullptr;
}

// ---------------------------------------------------------------------------
// Colour helpers
// ---------------------------------------------------------------------------

static uint8_t nmul(uint8_t a, uint8_t b)
{
    return (uint8_t)((((uint16_t)a + 1) * b) >> 8);
}

RGBAColour lerp_colour(RGBAColour lhs, RGBAColour rhs, uint8_t factor)
{
    return {
        (uint8_t)(nmul(lhs.r, 255 - factor) + nmul(rhs.r, factor)),
        (uint8_t)(nmul(lhs.g, 255 - factor) + nmul(rhs.g, factor)),
        (uint8_t)(nmul(lhs.b, 255 - factor) + nmul(rhs.b, factor)),
        (uint8_t)(nmul(lhs.a, 255 - factor) + nmul(rhs.a, factor)),
    };
}

static RGBAColour blerp_colour(RGBAColour tl, RGBAColour tr,
                               RGBAColour bl, RGBAColour br,
                               uint8_t fx, uint8_t fy)
{
    return lerp_colour(lerp_colour(tl, tr, fx), lerp_colour(bl, br, fx), fy);
}

// ---------------------------------------------------------------------------
// Image loading — Core Graphics / ImageIO
// ---------------------------------------------------------------------------

static Image cgimage_to_image(CGImageRef cg_img)
{
    if(!cg_img) return {};

    const size_t w = CGImageGetWidth(cg_img);
    const size_t h = CGImageGetHeight(cg_img);
    const size_t bytes = w * h * 4;

    uint8_t* pixels = (uint8_t*)malloc(bytes);
    if(!pixels) return {};

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if(!ctx) { free(pixels); return {}; }

    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg_img);
    CGContextRelease(ctx);

    // Un-premultiply alpha
    for(size_t i = 0; i < bytes; i += 4)
    {
        uint8_t a = pixels[i + 3];
        if(a > 0 && a < 255)
        {
            pixels[i]     = (uint8_t)((pixels[i]     * 255u + a / 2) / a);
            pixels[i + 1] = (uint8_t)((pixels[i + 1] * 255u + a / 2) / a);
            pixels[i + 2] = (uint8_t)((pixels[i + 2] * 255u + a / 2) / a);
        }
    }

    Image result;
    result.pixels = pixels;
    result.width  = (int)w;
    result.height = (int)h;
    return result;
}

std::optional<Image> load_image(const char* file_path)
{
    NSString* path_str = [NSString stringWithUTF8String:file_path];
    NSURL* url = [NSURL fileURLWithPath:path_str];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if(!src)
    {
        LOG_INFO("Failed to open image: %s", file_path);
        return {};
    }

    CGImageRef cg_img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if(!cg_img)
    {
        LOG_INFO("Failed to decode image: %s", file_path);
        return {};
    }

    Image result = cgimage_to_image(cg_img);
    CGImageRelease(cg_img);
    if(!result.valid()) return {};
    return result;
}

std::optional<Image> decode_image(const void* input_buffer, size_t input_buffer_length)
{
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
                                                 (const UInt8*)input_buffer,
                                                 (CFIndex)input_buffer_length,
                                                 kCFAllocatorNull);
    if(!data) return {};

    CGImageSourceRef src = CGImageSourceCreateWithData(data, nullptr);
    CFRelease(data);
    if(!src)
    {
        LOG_INFO("Failed to decode image from memory");
        return {};
    }

    CGImageRef cg_img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if(!cg_img)
    {
        LOG_INFO("Failed to create CGImage from decoded data");
        return {};
    }

    Image result = cgimage_to_image(cg_img);
    CGImageRelease(cg_img);
    if(!result.valid()) return {};
    return result;
}

// ---------------------------------------------------------------------------
// Background generation — pure pixel math (same as Windows)
// ---------------------------------------------------------------------------

Image generate_background_colour(int width, int height, RGBAColour colour)
{
    if(width <= 0 || height <= 0) return {};
    uint8_t* pixels = (uint8_t*)malloc((size_t)width * (size_t)height * 4);
    if(!pixels) return {};

    for(int i = 0; i < width * height; i++)
    {
        pixels[i * 4]     = colour.r;
        pixels[i * 4 + 1] = colour.g;
        pixels[i * 4 + 2] = colour.b;
        pixels[i * 4 + 3] = 255;
    }

    Image result;
    result.pixels = pixels;
    result.width  = width;
    result.height = height;
    return result;
}

Image generate_background_colour(int width, int height,
                                 RGBAColour topleft, RGBAColour topright,
                                 RGBAColour botleft, RGBAColour botright)
{
    if(width <= 0 || height <= 0) return {};
    uint8_t* pixels = (uint8_t*)malloc((size_t)width * (size_t)height * 4);
    if(!pixels) return {};

    for(int y = 0; y < height; y++)
    {
        const uint8_t fy = (uint8_t)(((255 * y) / (height - 1)) & 0xFF);
        for(int x = 0; x < width; x++)
        {
            const uint8_t fx = (uint8_t)(((255 * x) / (width - 1)) & 0xFF);
            const RGBAColour c = blerp_colour(topleft, topright, botleft, botright, fx, fy);
            uint8_t* px = pixels + 4 * (y * width + x);
            px[0] = c.r; px[1] = c.g; px[2] = c.b; px[3] = 255;
        }
    }

    Image result;
    result.pixels = pixels;
    result.width  = width;
    result.height = height;
    return result;
}

// ---------------------------------------------------------------------------
// Image interpolation — pure pixel math (same as Windows)
// ---------------------------------------------------------------------------

Image lerp_image(const Image& lhs, const Image& rhs, double t)
{
    if(!lhs.valid() || !rhs.valid()) return {};

    const uint8_t factor = (uint8_t)(255.0 * t);
    uint8_t* pixels = (uint8_t*)malloc((size_t)lhs.width * (size_t)lhs.height * 4);
    if(!pixels) return {};

    for(int i = 0; i < lhs.width * lhs.height; i++)
    {
        const int off = i * 4;
        RGBAColour lc = *((const RGBAColour*)(lhs.pixels + off));
        RGBAColour rc = *((const RGBAColour*)(rhs.pixels + off));
        RGBAColour oc = lerp_colour(lc, rc, factor);
        pixels[off]     = oc.r;
        pixels[off + 1] = oc.g;
        pixels[off + 2] = oc.b;
        pixels[off + 3] = 255;
    }

    Image result;
    result.pixels = pixels;
    result.width  = lhs.width;
    result.height = lhs.height;
    return result;
}

Image lerp_offset_image(const Image& full_img, const Image& offset_img, CPoint offset, double t)
{
    if(!full_img.valid() || !offset_img.valid()) return {};

    const uint8_t factor = (uint8_t)(255.0 * t);
    uint8_t* pixels = (uint8_t*)malloc((size_t)full_img.width * (size_t)full_img.height * 4);
    if(!pixels) return {};

    memcpy(pixels, full_img.pixels, (size_t)full_img.width * (size_t)offset.y * 4);

    for(int y = 0; y < offset_img.height; y++)
    {
        const int full_y = offset.y + y;
        uint8_t* out_row       = pixels          + 4 * full_img.width * full_y;
        const uint8_t* in_full = full_img.pixels  + 4 * full_img.width * full_y;
        const uint8_t* in_off  = offset_img.pixels + 4 * offset_img.width * y;

        memcpy(out_row, in_full, (size_t)offset.x * 4);

        for(int x = 0; x < offset_img.width; x++)
        {
            const int fx = offset.x + x;
            RGBAColour fc = *((const RGBAColour*)(in_full + 4 * fx));
            RGBAColour oc_in = *((const RGBAColour*)(in_off  + 4 * x));
            RGBAColour out   = lerp_colour(fc, oc_in, factor);
            uint8_t* dst = out_row + 4 * fx;
            dst[0] = out.r; dst[1] = out.g; dst[2] = out.b; dst[3] = 255;
        }

        const int after_off = offset.x + offset_img.width;
        const int remaining = full_img.width - after_off;
        if(remaining > 0)
            memcpy(out_row + 4 * after_off, in_full + 4 * after_off, (size_t)remaining * 4);
    }

    const int rows_above_or_at = offset.y + offset_img.height;
    const int rows_below = full_img.height - rows_above_or_at;
    if(rows_below > 0)
    {
        memcpy(pixels          + 4 * full_img.width * rows_above_or_at,
               full_img.pixels + 4 * full_img.width * rows_above_or_at,
               (size_t)full_img.width * (size_t)rows_below * 4);
    }

    Image result;
    result.pixels = pixels;
    result.width  = full_img.width;
    result.height = full_img.height;
    return result;
}

// ---------------------------------------------------------------------------
// Image resize — Core Graphics
// ---------------------------------------------------------------------------

Image resize_image(const Image& input, int out_width, int out_height)
{
    if(!input.valid() || out_width <= 0 || out_height <= 0) return {};

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

    // Wrap input pixels in a CGContext (read-only via CGBitmapContext)
    CGContextRef src_ctx = CGBitmapContextCreate(input.pixels,
                                                 (size_t)input.width, (size_t)input.height,
                                                 8, (size_t)input.width * 4, cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if(!src_ctx) { CGColorSpaceRelease(cs); return {}; }

    CGImageRef src_img = CGBitmapContextCreateImage(src_ctx);
    CGContextRelease(src_ctx);
    if(!src_img) { CGColorSpaceRelease(cs); return {}; }

    uint8_t* out_pixels = (uint8_t*)malloc((size_t)out_width * (size_t)out_height * 4);
    if(!out_pixels) { CGImageRelease(src_img); CGColorSpaceRelease(cs); return {}; }

    CGContextRef dst_ctx = CGBitmapContextCreate(out_pixels,
                                                 (size_t)out_width, (size_t)out_height,
                                                 8, (size_t)out_width * 4, cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if(!dst_ctx) { CGImageRelease(src_img); free(out_pixels); return {}; }

    CGContextSetInterpolationQuality(dst_ctx, kCGInterpolationHigh);
    CGContextDrawImage(dst_ctx, CGRectMake(0, 0, out_width, out_height), src_img);
    CGContextRelease(dst_ctx);
    CGImageRelease(src_img);

    Image result;
    result.pixels = out_pixels;
    result.width  = out_width;
    result.height = out_height;
    return result;
}

// ---------------------------------------------------------------------------
// Transpose — pure pixel math (same as Windows, block-based for cache efficiency)
// ---------------------------------------------------------------------------

static void transpose_noalloc(int width, int height, const uint8_t* in, uint8_t* out)
{
    const int block = 256;
    for(int by = 0; by < height; by += block)
    {
        for(int x = 0; x < width; x++)
        {
            const uint8_t* in_col = in + 4 * (by * width + x);
            uint8_t* out_row = out + 4 * (x * height + by);
            for(int y = 0; (y < block) && (by + y < height); y++)
            {
                memcpy(out_row + 4 * y, in_col + 4 * y * width, 4);
            }
        }
    }
}

Image transpose_image(const Image& img)
{
    if(!img.valid()) return {};
    uint8_t* pixels = (uint8_t*)malloc((size_t)img.width * (size_t)img.height * 4);
    if(!pixels) return {};
    transpose_noalloc(img.width, img.height, img.pixels, pixels);
    Image result;
    result.pixels = pixels;
    result.width  = img.height;
    result.height = img.width;
    return result;
}

// ---------------------------------------------------------------------------
// Blur — vImage box convolve (3-pass approximates Gaussian, same strategy as
// the Windows version which does 3 horizontal box blurs + transpose trick)
// ---------------------------------------------------------------------------

static Image hblur_vimage(const Image& img, int radius)
{
    uint8_t* out = (uint8_t*)malloc((size_t)img.width * (size_t)img.height * 4);
    if(!out) return {};

    vImage_Buffer src = { img.pixels, (vImagePixelCount)img.height, (vImagePixelCount)img.width, (size_t)img.width * 4 };
    vImage_Buffer dst = { out,        (vImagePixelCount)img.height, (vImagePixelCount)img.width, (size_t)img.width * 4 };

    // kernel width must be odd
    uint32_t kw = (uint32_t)(2 * radius + 1);
    uint32_t kh = 1;
    vImage_Error err = vImageBoxConvolve_ARGB8888(&src, &dst, nullptr, 0, 0, kh, kw,
                                                  nullptr, kvImageEdgeExtend);
    if(err != kvImageNoError)
    {
        free(out);
        return {};
    }

    Image result;
    result.pixels = out;
    result.width  = img.width;
    result.height = img.height;
    return result;
}

Image blur_image(const Image& img, int radius)
{
    if(!img.valid()) return {};

    if(radius > img.width / 3)  radius = img.width / 3;
    if(radius > img.height / 3) radius = img.height / 3;

    if(radius <= 0)
    {
        const size_t bytes = (size_t)img.width * (size_t)img.height * 4;
        uint8_t* pixels = (uint8_t*)malloc(bytes);
        if(!pixels) return {};
        memcpy(pixels, img.pixels, bytes);
        Image result;
        result.pixels = pixels;
        result.width  = img.width;
        result.height = img.height;
        return result;
    }

    // Same strategy as Windows: 3x horizontal + transpose + 3x horizontal + transpose
    // approximates a separable Gaussian blur.
    Image transposed = transpose_image(img);
    if(!transposed.valid()) return {};

    Image vh1 = hblur_vimage(transposed, radius);
    if(!vh1.valid()) return {};
    Image vh2 = hblur_vimage(vh1, radius);
    if(!vh2.valid()) return {};
    Image vh3 = hblur_vimage(vh2, radius);
    if(!vh3.valid()) return {};

    Image untransed = transpose_image(vh3);
    if(!untransed.valid()) return {};

    Image h1 = hblur_vimage(untransed, radius);
    if(!h1.valid()) return {};
    Image h2 = hblur_vimage(h1, radius);
    if(!h2.valid()) return {};
    Image h3 = hblur_vimage(h2, radius);
    return h3;
}
