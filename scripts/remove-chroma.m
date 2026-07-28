#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static uint8_t ClampByte(double value) {
    return (uint8_t)MAX(0, MIN(255, round(value)));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "用法：remove-chroma <输入.png> <输出.png>\n");
            return 2;
        }

        NSURL *inputURL = [NSURL fileURLWithPath:@(argv[1])];
        NSURL *outputURL = [NSURL fileURLWithPath:@(argv[2])];
        CGImageSourceRef source =
            CGImageSourceCreateWithURL((__bridge CFURLRef)inputURL, NULL);
        if (source == NULL) {
            fprintf(stderr, "无法读取输入图片\n");
            return 1;
        }

        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (image == NULL) {
            fprintf(stderr, "无法解码输入图片\n");
            return 1;
        }

        size_t width = CGImageGetWidth(image);
        size_t height = CGImageGetHeight(image);
        size_t bytesPerRow = width * 4;
        uint8_t *pixels = calloc(height, bytesPerRow);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(
            pixels,
            width,
            height,
            8,
            bytesPerRow,
            colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
        );
        CGColorSpaceRelease(colorSpace);

        if (pixels == NULL || context == NULL) {
            CGImageRelease(image);
            free(pixels);
            fprintf(stderr, "无法创建图像缓冲区\n");
            return 1;
        }

        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGImageRelease(image);

        double keyR = pixels[0];
        double keyG = pixels[1];
        double keyB = pixels[2];
        const double opaqueMagentaStrength = 70.0;
        const double transparentMagentaStrength = 220.0;
        size_t transparentPixelCount = 0;

        for (size_t offset = 0; offset < height * bytesPerRow; offset += 4) {
            double red = pixels[offset];
            double green = pixels[offset + 1];
            double blue = pixels[offset + 2];
            double magentaStrength = MIN(red, blue) - green;
            double alpha = (transparentMagentaStrength - magentaStrength) /
                (transparentMagentaStrength - opaqueMagentaStrength);
            alpha = MAX(0.0, MIN(1.0, alpha));

            if (alpha <= 0.001) {
                pixels[offset] = 0;
                pixels[offset + 1] = 0;
                pixels[offset + 2] = 0;
                pixels[offset + 3] = 0;
                transparentPixelCount += 1;
                continue;
            }

            double foregroundRed = (red - (1.0 - alpha) * keyR) / alpha;
            double foregroundGreen = (green - (1.0 - alpha) * keyG) / alpha;
            double foregroundBlue = (blue - (1.0 - alpha) * keyB) / alpha;
            pixels[offset] = ClampByte(foregroundRed * alpha);
            pixels[offset + 1] = ClampByte(foregroundGreen * alpha);
            pixels[offset + 2] = ClampByte(foregroundBlue * alpha);
            pixels[offset + 3] = ClampByte(alpha * 255.0);
        }

        CGImageRef outputImage = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        free(pixels);

        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)outputURL,
            (__bridge CFStringRef)UTTypePNG.identifier,
            1,
            NULL
        );
        if (destination == NULL || outputImage == NULL) {
            if (destination != NULL) {
                CFRelease(destination);
            }
            if (outputImage != NULL) {
                CGImageRelease(outputImage);
            }
            fprintf(stderr, "无法创建输出图片\n");
            return 1;
        }

        CGImageDestinationAddImage(destination, outputImage, NULL);
        BOOL succeeded = CGImageDestinationFinalize(destination);
        CFRelease(destination);
        CGImageRelease(outputImage);

        if (!succeeded) {
            fprintf(stderr, "无法写入输出图片\n");
            return 1;
        }
        fprintf(stdout, "透明像素：%zu / %zu\n", transparentPixelCount, width * height);
    }
    return 0;
}
