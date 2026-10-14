//
//  windows.m
//  Mousecape
//
//  Converts Windows cursor themes (.ani and .cur files) to capes.
//

#import "windows.h"
#import "NSBitmapImageRep+ColorSpace.h"

// Windows draws cursors 32 pixels wide at its default size and scale
static const CGFloat MCWindowsCursorPoints = 32.0;

// Windows pointer roles, named as in HKCU\Control Panel\Cursors, and the macOS cursors doing the same job.
// Handwriting, Alternate, Location and Person have no counterpart.
static NSArray *identifiersForRole(NSString *role) {
    static NSDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = [@{
            @"arrow":       @[ @"com.apple.coregraphics.Arrow" ],
            @"ibeam":       @[ @"com.apple.coregraphics.IBeam" ],
            @"wait":        @[ @"com.apple.coregraphics.Wait" ],
            @"appstarting": @[ @"com.apple.cursor.4" ],
            @"no":          @[ @"com.apple.cursor.3" ],
            @"crosshair":   @[ @"com.apple.cursor.7", @"com.apple.cursor.8" ],
            @"hand":        @[ @"com.apple.cursor.13" ],
            @"help":        @[ @"com.apple.cursor.40" ],
            @"sizeall":     @[ @"com.apple.cursor.39" ],
            @"sizewe":      @[ @"com.apple.cursor.17", @"com.apple.cursor.18", @"com.apple.cursor.19",
                               @"com.apple.cursor.27", @"com.apple.cursor.28", @"com.apple.cursor.38" ],
            @"sizens":      @[ @"com.apple.cursor.21", @"com.apple.cursor.22", @"com.apple.cursor.23",
                               @"com.apple.cursor.31", @"com.apple.cursor.32", @"com.apple.cursor.36" ],
            @"sizenwse":    @[ @"com.apple.cursor.33", @"com.apple.cursor.34", @"com.apple.cursor.35" ],
            @"sizenesw":    @[ @"com.apple.cursor.29", @"com.apple.cursor.30", @"com.apple.cursor.37" ],
        } retain];
    });
    return map[role];
}

// The order of the files in a Control Panel\Cursors\Schemes value
static NSArray *schemeRoles(void) {
    return @[ @"arrow", @"help", @"appstarting", @"wait", @"crosshair", @"ibeam", @"nwpen", @"no", @"sizens",
              @"sizewe", @"sizenwse", @"sizenesw", @"sizeall", @"uparrow", @"hand", @"pin", @"person" ];
}

// Guesses a file's role from its name when there is no .inf: the names Windows itself uses in
// English, Chinese and Japanese, and the registry names. More specific names come first.
static NSString *roleForFileName(NSString *fileName) {
    NSString *name = fileName.stringByDeletingPathExtension.lowercaseString;
    for (NSString *separator in @[ @" ", @"_", @"-", @".", @"(", @")" ])
        name = [name stringByReplacingOccurrencesOfString:separator withString:@""];

    NSDictionary *exact = @{ @"no": @"no", @"ns": @"sizens", @"we": @"sizewe", @"nwse": @"sizenwse", @"nesw": @"sizenesw",
                             @"cross": @"crosshair", @"pen": @"nwpen", @"pin": @"pin", @"up": @"uparrow" };
    if (exact[name])
        return exact[name];

    BOOL diagonal = [name containsString:@"diag"] || [name containsString:@"dgn"] || [name containsString:@"对角"] ||
                    [name containsString:@"對角"] || [name containsString:@"斜め"];
    if (diagonal && [name hasSuffix:@"1"])
        return @"sizenwse";
    if (diagonal && [name hasSuffix:@"2"])
        return @"sizenesw";

    NSArray *rules = @[
        @[ @"nwpen",       @[ @"handwriting", @"nwpen", @"手写", @"手寫", @"手書き" ] ],
        @[ @"hand",        @[ @"link", @"hand", @"链接", @"連結", @"リンク" ] ],
        @[ @"help",        @[ @"help", @"帮助", @"說明", @"ヘルプ" ] ],
        @[ @"appstarting", @[ @"working", @"appstarting", @"background", @"progress", @"后台", @"背景", @"バックグラウンド" ] ],
        @[ @"wait",        @[ @"busy", @"wait", @"忙", @"等待", @"待ち" ] ],
        @[ @"crosshair",   @[ @"precision", @"crosshair", @"cross", @"精确", @"精確", @"十字", @"領域" ] ],
        @[ @"ibeam",       @[ @"text", @"ibeam", @"beam", @"文本", @"文字", @"テキスト" ] ],
        @[ @"no",          @[ @"unavailable", @"forbidden", @"notallowed", @"不可用", @"無法使用", @"禁止", @"利用不可" ] ],
        @[ @"sizenwse",    @[ @"nwse" ] ],
        @[ @"sizenesw",    @[ @"nesw" ] ],
        @[ @"sizens",      @[ @"vertical", @"sizens", @"vert", @"垂直", @"上下" ] ],
        @[ @"sizewe",      @[ @"horizontal", @"sizewe", @"horz", @"horiz", @"水平", @"左右" ] ],
        @[ @"sizeall",     @[ @"move", @"sizeall", @"移动", @"移動" ] ],
        @[ @"uparrow",     @[ @"alternate", @"uparrow", @"候选", @"候選", @"代替" ] ],
        @[ @"pin",         @[ @"location", @"位置", @"場所" ] ],
        @[ @"person",      @[ @"person", @"个人", @"個人", @"人员", @"ユーザー" ] ],
        @[ @"arrow",       @[ @"normal", @"arrow", @"pointer", @"default", @"正常", @"标准", @"標準", @"通常" ] ],
    ];
    for (NSArray *rule in rules) {
        for (NSString *word in rule[1]) {
            if ([name containsString:word])
                return rule[0];
        }
    }
    return nil;
}

#pragma mark - Reading files

static inline uint16_t read16(const uint8_t *p) {
    return (uint16_t)(p[0] | p[1] << 8);
}

static inline uint32_t read32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

// Text from an .inf or an .ani's INFO chunk: UTF-16 with a byte order mark, UTF-8, or the ANSI code
// pages these files are usually saved in
static NSString *stringFromTextData(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSString *string = nil;
    if (data.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF)))
        string = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
    if (!string)
        string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!string)
        string = [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
    if (!string)
        string = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];

    NSMutableCharacterSet *trimmed = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [trimmed addCharactersInString:@"﻿"];
    [trimmed addCharactersInRange:NSMakeRange(0, 1)];
    return [[string autorelease] stringByTrimmingCharactersInSet:trimmed];
}

// An .inf line's comma separated fields, without their quotes
static NSArray *infFields(NSString *line) {
    NSMutableArray *fields = [NSMutableArray array];
    NSMutableString *field = [NSMutableString string];
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == '"') {
            quoted = !quoted;
        } else if (c == ',' && !quoted) {
            [fields addObject:[field stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
            [field setString:@""];
        } else if (c == ';' && !quoted) {
            break;
        } else {
            [field appendFormat:@"%C", c];
        }
    }
    [fields addObject:[field stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    return fields;
}

// The file named for each role in an install.inf, by lower case file name, and the scheme's name
static NSDictionary *rolesFromInf(NSString *path, NSString **schemeName) {
    NSString *text = stringFromTextData([NSData dataWithContentsOfFile:path]);
    if (!text)
        return nil;

    NSMutableDictionary *strings = [NSMutableDictionary dictionary];
    NSMutableArray *registryLines = [NSMutableArray array];
    NSString *section = nil;
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!line.length || [line hasPrefix:@";"])
            continue;
        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
            section = [line substringWithRange:NSMakeRange(1, line.length - 2)].lowercaseString;
        } else if ([section isEqualToString:@"strings"]) {
            NSRange equals = [line rangeOfString:@"="];
            if (equals.location == NSNotFound)
                continue;
            NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *value = [[line substringFromIndex:NSMaxRange(equals)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
            strings[key.lowercaseString] = value;
        } else if ([line.lowercaseString hasPrefix:@"hkcu,"]) {
            [registryLines addObject:line];
        }
    }

    // %name% stands for a string; Windows' own (%10% is its folder) only matter before the file name
    NSString *(^expand)(NSString *) = ^NSString *(NSString *value) {
        NSMutableString *result = [NSMutableString stringWithString:value];
        for (NSUInteger pass = 0; pass < 4 && [result containsString:@"%"]; pass++) {
            for (NSString *key in strings) {
                [result replaceOccurrencesOfString:[NSString stringWithFormat:@"%%%@%%", key] withString:strings[key]
                                           options:NSCaseInsensitiveSearch range:NSMakeRange(0, result.length)];
            }
        }
        return result;
    };
    NSString *(^fileName)(NSString *) = ^NSString *(NSString *value) {
        return [expand(value) componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\\/"]].lastObject.lowercaseString;
    };

    NSMutableDictionary *roles = [NSMutableDictionary dictionary];
    NSArray *schemeFiles = nil;
    for (NSString *line in registryLines) {
        NSArray *fields = infFields(line);
        if (fields.count < 5)
            continue;
        NSString *key = [fields[1] lowercaseString];
        if ([key isEqualToString:@"control panel\\cursors"] && [fields[2] length] && [fields[4] length]) {
            roles[[fields[2] lowercaseString]] = fileName(fields[4]);
        } else if ([key isEqualToString:@"control panel\\cursors\\schemes"]) {
            schemeFiles = [expand(fields[4]) componentsSeparatedByString:@","];
            if (schemeName && [fields[2] length])
                *schemeName = expand(fields[2]);
        }
    }

    // Themes that only list the scheme name their files in a fixed order
    NSArray *order = schemeRoles();
    for (NSUInteger i = 0; i < MIN(order.count, schemeFiles.count); i++) {
        NSString *file = fileName(schemeFiles[i]);
        if (!roles[order[i]] && file.length)
            roles[order[i]] = file;
    }

    if (schemeName && strings[@"scheme_name"])
        *schemeName = strings[@"scheme_name"];
    return roles;
}

#pragma mark - Images

// One image from a .cur or .ico (or an .ani frame): its size, where it points in its own pixels, and
// its PNG or bitmap data. Themes often carry each frame at five sizes, so only the ones drawn get decoded.
@interface MCWindowsImage : NSObject {
@public
    NSData *data;
    size_t width, height;
    CGPoint hotSpot;
    CGImageRef decoded;
}
- (CGImageRef)image;
@end

static CGContextRef createContext(void *data, size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, data ? width * 4 : 0, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    return context;
}

// A device independent bitmap as stored in icons: the colors, then a 1-bit mask, both bottom up,
// with the height counting both
static CGImageRef createImageFromDIB(const uint8_t *bytes, size_t length) {
    if (length < 40)
        return NULL;
    uint32_t headerSize = read32(bytes), compression = read32(bytes + 16), used = read32(bytes + 32);
    int32_t width = (int32_t)read32(bytes + 4), doubleHeight = (int32_t)read32(bytes + 8);
    uint16_t bits = read16(bytes + 14);
    BOOL topDown = doubleHeight < 0;
    int32_t height = abs(doubleHeight) / 2;
    if (headerSize < 40 || headerSize > length || width <= 0 || height <= 0 || width > 1024 || height > 1024)
        return NULL;
    if (bits != 1 && bits != 4 && bits != 8 && bits != 24 && bits != 32)
        return NULL;
    // Uncompressed, or 32-bit with the usual channel masks
    if (compression != 0 && !(compression == 3 && bits == 32))
        return NULL;

    size_t position = headerSize + (compression == 3 && headerSize == 40 ? 12 : 0);
    uint32_t colors = bits <= 8 ? (used ? used : 1u << bits) : 0;
    if (colors > 256 || position + 4 * colors > length)
        return NULL;
    const uint8_t *palette = bytes + position;
    position += 4 * colors;

    size_t stride = ((size_t)width * bits + 31) / 32 * 4, maskStride = ((size_t)width + 31) / 32 * 4;
    if (position + stride * height > length)
        return NULL;
    const uint8_t *pixels = bytes + position;
    position += stride * height;
    const uint8_t *mask = position + maskStride * height <= length ? bytes + position : NULL;

    // 32-bit images with any alpha use it, and Windows ignores their mask
    BOOL hasAlpha = NO;
    for (int32_t y = 0; bits == 32 && y < height && !hasAlpha; y++)
        for (int32_t x = 0; x < width && !hasAlpha; x++)
            hasAlpha = pixels[y * stride + 4 * x + 3] != 0;

    uint8_t *rgba = calloc((size_t)width * height, 4);
    uint8_t *inverted = calloc((size_t)width * height, 1);
    BOOL anyInverted = NO;
    for (int32_t row = 0; row < height; row++) {
        int32_t y = topDown ? row : height - 1 - row;
        const uint8_t *source = pixels + row * stride;
        const uint8_t *maskRow = mask ? mask + row * maskStride : NULL;
        for (int32_t x = 0; x < width; x++) {
            uint8_t r, g, b, a = 255;
            if (bits == 32) {
                b = source[4 * x]; g = source[4 * x + 1]; r = source[4 * x + 2];
                if (hasAlpha)
                    a = source[4 * x + 3];
            } else if (bits == 24) {
                b = source[3 * x]; g = source[3 * x + 1]; r = source[3 * x + 2];
            } else {
                unsigned perByte = 8 / bits;
                unsigned index = (source[x / perByte] >> ((perByte - 1 - x % perByte) * bits)) & ((1u << bits) - 1);
                if (index >= colors)
                    index = 0;
                b = palette[4 * index]; g = palette[4 * index + 1]; r = palette[4 * index + 2];
            }

            size_t i = (size_t)y * width + x;
            if (!hasAlpha && maskRow && (maskRow[x / 8] >> (7 - x % 8)) & 1) {
                // Masked out: see-through, or a color meaning "invert what's underneath"
                if (r | g | b) {
                    inverted[i] = 1;
                    anyInverted = YES;
                }
                continue;
            }
            rgba[4 * i]     = r * a / 255;
            rgba[4 * i + 1] = g * a / 255;
            rgba[4 * i + 2] = b * a / 255;
            rgba[4 * i + 3] = a;
        }
    }

    // macOS cursors can't invert the screen, so those pixels become black with a white edge,
    // which reads on any background
    if (anyInverted) {
        for (size_t i = 0; i < (size_t)width * height; i++) {
            if (inverted[i]) {
                rgba[4 * i] = rgba[4 * i + 1] = rgba[4 * i + 2] = 0;
                rgba[4 * i + 3] = 255;
            }
        }
        for (int32_t y = 0; y < height; y++) {
            for (int32_t x = 0; x < width; x++) {
                size_t i = (size_t)y * width + x;
                if (rgba[4 * i + 3])
                    continue;
                BOOL edge = NO;
                for (int32_t dy = -1; dy <= 1 && !edge; dy++)
                    for (int32_t dx = -1; dx <= 1 && !edge; dx++)
                        edge = y + dy >= 0 && y + dy < height && x + dx >= 0 && x + dx < width && inverted[(size_t)(y + dy) * width + x + dx];
                if (edge)
                    memset(rgba + 4 * i, 255, 4);
            }
        }
    }

    CGContextRef context = createContext(rgba, width, height);
    CGImageRef image = context ? CGBitmapContextCreateImage(context) : NULL;
    CGContextRelease(context);
    free(rgba);
    free(inverted);
    return image;
}

// PNG images, which icons may hold since Windows Vista, redrawn in sRGB
static CGImageRef createImageFromPNG(NSData *data) {
    CGImageRef source = [[NSBitmapImageRep imageRepWithData:data] CGImage];
    if (!source)
        return NULL;
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    CGContextRef context = createContext(NULL, width, height);
    if (!context)
        return NULL;
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

static BOOL isPNG(const uint8_t *bytes, size_t length) {
    return length >= 24 && !memcmp(bytes, "\x89PNG", 4);
}

@implementation MCWindowsImage

- (CGImageRef)image {
    if (!decoded)
        decoded = isPNG(data.bytes, data.length) ? createImageFromPNG(data) : createImageFromDIB(data.bytes, data.length);
    return decoded;
}

- (void)dealloc {
    CGImageRelease(decoded);
    [data release];
    [super dealloc];
}

@end

// The images in a .cur or .ico, or an .ani frame, smallest first. Sizes come from the images' own
// headers, since the directory can't say 256 and is sometimes wrong.
static NSArray *imagesInIcon(NSData *data) {
    const uint8_t *bytes = data.bytes;
    size_t length = data.length;
    if (length < 6 || read16(bytes) != 0)
        return nil;
    uint16_t type = read16(bytes + 2), count = read16(bytes + 4);
    if ((type != 1 && type != 2) || count == 0 || 6 + 16 * (size_t)count > length)
        return nil;

    NSMutableArray *images = [NSMutableArray array];
    for (uint16_t k = 0; k < count; k++) {
        const uint8_t *entry = bytes + 6 + 16 * k;
        uint32_t size = read32(entry + 8), offset = read32(entry + 12);
        if (offset > length || size > length - offset || size < 8)
            continue;
        const uint8_t *blob = bytes + offset;
        size_t width, height;
        if (isPNG(blob, size)) {
            width = (size_t)blob[16] << 24 | (size_t)blob[17] << 16 | (size_t)blob[18] << 8 | blob[19];
            height = (size_t)blob[20] << 24 | (size_t)blob[21] << 16 | (size_t)blob[22] << 8 | blob[23];
        } else if (size >= 40) {
            width = (size_t)abs((int32_t)read32(blob + 4));
            height = (size_t)abs((int32_t)read32(blob + 8)) / 2;
        } else {
            continue;
        }
        if (width < 1 || height < 1 || width > 1024 || height > 1024)
            continue;

        MCWindowsImage *item = [[[MCWindowsImage alloc] init] autorelease];
        item->data = [[NSData alloc] initWithBytes:blob length:size];
        item->width = width;
        item->height = height;
        // Icons used as cursors point from their corner
        item->hotSpot = type == 2 ? CGPointMake(read16(entry + 4), read16(entry + 6)) : CGPointZero;
        [images addObject:item];
    }
    [images sortUsingComparator:^NSComparisonResult(MCWindowsImage *a, MCWindowsImage *b) {
        size_t wa = a->width, wb = b->width;
        return wa < wb ? NSOrderedAscending : wa > wb ? NSOrderedDescending : NSOrderedSame;
    }];
    return images.count ? images : nil;
}

// An .ani's frames in play order, each an array of images, with how many 1/60 s each shows
static BOOL readAnimatedCursor(NSData *data, NSMutableArray *steps, NSMutableArray *jiffies, NSString **title, NSString **artist) {
    const uint8_t *bytes = data.bytes;
    size_t length = data.length;
    if (length < 12 || memcmp(bytes, "RIFF", 4) || memcmp(bytes + 8, "ACON", 4))
        return NO;

    uint32_t defaultJiffies = 10, flags = 1;
    const uint8_t *rates = NULL, *sequence = NULL;
    size_t rateCount = 0, sequenceCount = 0;
    NSMutableArray *icons = [NSMutableArray array];

    for (size_t position = 12; position + 8 <= length; ) {
        const uint8_t *chunk = bytes + position;
        size_t start = position + 8, size = MIN((size_t)read32(chunk + 4), length - start);
        const uint8_t *body = bytes + start;
        if (!memcmp(chunk, "anih", 4) && size >= 36) {
            defaultJiffies = read32(body + 28);
            flags = read32(body + 32);
        } else if (!memcmp(chunk, "rate", 4)) {
            rates = body;
            rateCount = size / 4;
        } else if (!memcmp(chunk, "seq ", 4)) {
            sequence = body;
            sequenceCount = size / 4;
        } else if (!memcmp(chunk, "LIST", 4) && size >= 4) {
            BOOL frames = !memcmp(body, "fram", 4), info = !memcmp(body, "INFO", 4);
            for (size_t sub = 4; sub + 8 <= size; ) {
                size_t subSize = MIN((size_t)read32(body + sub + 4), size - sub - 8);
                NSData *subData = [NSData dataWithBytes:body + sub + 8 length:subSize];
                if (frames && !memcmp(body + sub, "icon", 4))
                    [icons addObject:subData];
                else if (info && !memcmp(body + sub, "INAM", 4) && title)
                    *title = stringFromTextData(subData);
                else if (info && !memcmp(body + sub, "IART", 4) && artist)
                    *artist = stringFromTextData(subData);
                sub += 8 + subSize + (subSize & 1);
            }
        }
        position = start + size + (size & 1);
    }

    // Frames stored as raw bitmaps instead of icons are rare enough to leave out
    if (!(flags & 1) || !icons.count)
        return NO;

    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:icons.count];
    for (NSData *icon in icons) {
        NSArray *images = imagesInIcon(icon);
        if (!images)
            return NO;
        [frames addObject:images];
    }

    NSUInteger stepCount = sequence ? sequenceCount : frames.count;
    for (NSUInteger step = 0; step < stepCount; step++) {
        NSUInteger frame = sequence ? read32(sequence + 4 * step) : step;
        if (frame >= frames.count)
            return NO;
        uint32_t duration = rates && step < rateCount ? read32(rates + 4 * step) : defaultJiffies;
        [steps addObject:frames[frame]];
        [jiffies addObject:@(MAX(duration, 1u))];
    }
    return steps.count > 0;
}

// The smallest image at least this wide, or the largest one
static MCWindowsImage *imageForWidth(NSArray *images, size_t width) {
    for (MCWindowsImage *image in images) {
        if (image->width >= width)
            return image;
    }
    return images.lastObject;
}

static NSUInteger greatestCommonDivisor(NSUInteger a, NSUInteger b) {
    while (b) {
        NSUInteger t = a % b;
        a = b;
        b = t;
    }
    return a;
}

// A cape cursor from a .cur or .ani file, or nil if it can't be read
static NSDictionary *cursorFromWindowsFile(NSString *path, NSString **title, NSString **artist) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data)
        return nil;

    NSMutableArray *steps = [NSMutableArray array], *jiffies = [NSMutableArray array];
    if (data.length >= 4 && !memcmp(data.bytes, "RIFF", 4)) {
        if (!readAnimatedCursor(data, steps, jiffies, title, artist))
            return nil;
    } else {
        NSArray *images = imagesInIcon(data);
        if (!images)
            return nil;
        [steps addObject:images];
        [jiffies addObject:@60];
    }

    // Every frame of a cape shows for the same time. Steps of different lengths are repeated in a
    // shorter unit when the frames fit, and otherwise all take the average.
    NSUInteger unit = 0, total = 0;
    for (NSNumber *step in jiffies) {
        unit = greatestCommonDivisor(unit, step.unsignedIntegerValue);
        total += step.unsignedIntegerValue;
    }
    NSMutableArray *frames = [NSMutableArray array];
    NSTimeInterval duration;
    if (total / unit <= MAX((NSUInteger)MCMaxFrameCount, steps.count)) {
        for (NSUInteger i = 0; i < steps.count; i++) {
            for (NSUInteger repeat = 0; repeat < [jiffies[i] unsignedIntegerValue] / unit; repeat++)
                [frames addObject:steps[i]];
        }
        duration = unit / 60.0;
    } else {
        [frames addObjectsFromArray:steps];
        duration = total / 60.0 / steps.count;
    }

    // Sized as Windows draws it by default, with the hot spot from the sharpest image
    MCWindowsImage *largest = [frames[0] lastObject];
    CGFloat sourceWidth = largest->width, sourceHeight = largest->height;
    CGSize points = CGSizeMake(MCWindowsCursorPoints, MAX(1, round(MCWindowsCursorPoints * sourceHeight / sourceWidth)));
    CGFloat factor = MCWindowsCursorPoints / sourceWidth;
    CGPoint hotSpot = CGPointMake(MIN(largest->hotSpot.x * factor, points.width - 1), MIN(largest->hotSpot.y * factor, points.height - 1));

    // 1x and 2x, the scales macOS uses at the default pointer size. Pixel art scaled by whole numbers
    // stays sharp; anything else is resampled smoothly.
    NSMutableArray *representations = [NSMutableArray array];
    for (size_t scale = 1; scale <= 2; scale++) {
        size_t width = points.width * scale, height = points.height * scale;
        CGContextRef context = createContext(NULL, width, height * frames.count);
        if (!context)
            return nil;
        for (NSUInteger i = 0; i < frames.count; i++) {
            CGImageRef source = [imageForWidth(frames[i], width) image];
            if (!source) {
                CGContextRelease(context);
                return nil;
            }
            size_t sw = CGImageGetWidth(source), sh = CGImageGetHeight(source);
            BOOL whole = width % sw == 0 && height % sh == 0 && width / sw == height / sh;
            CGContextSetInterpolationQuality(context, whole ? kCGInterpolationNone : kCGInterpolationHigh);
            CGContextDrawImage(context, CGRectMake(0, (frames.count - 1 - i) * height, width, height), source);
        }
        CGImageRef strip = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        if (!strip)
            return nil;
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage:strip] autorelease];
        CGImageRelease(strip);
        [representations addObject:[rep.ensuredSRGBSpace TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1.0]];
    }

    NSMutableDictionary *cursor = [NSMutableDictionary dictionary];
    [cursor setObject:@(frames.count) forKey:(id)MCCursorDictionaryFrameCountKey];
    [cursor setObject:@(duration) forKey:(id)MCCursorDictionaryFrameDuratiomKey];
    [cursor setObject:@(hotSpot.x) forKey:(id)MCCursorDictionaryHotSpotXKey];
    [cursor setObject:@(hotSpot.y) forKey:(id)MCCursorDictionaryHotSpotYKey];
    [cursor setObject:@(points.width) forKey:(id)MCCursorDictionaryPointsWideKey];
    [cursor setObject:@(points.height) forKey:(id)MCCursorDictionaryPointsHighKey];
    [cursor setObject:representations forKey:(id)MCCursorDictionaryRepresentationsKey];
    return cursor;
}

#pragma mark - Themes

static BOOL isCursorFile(NSString *path) {
    NSString *extension = path.pathExtension.lowercaseString;
    return [extension isEqualToString:@"ani"] || [extension isEqualToString:@"cur"];
}

// Cursor files and .inf files in a folder and the folders inside it, shallowest first, then by name
static void collectThemeFiles(NSString *folder, NSMutableArray *cursors, NSMutableArray *infs) {
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:folder]
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
                                                                         errorHandler:nil];
    NSMutableArray *found = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        if (enumerator.level > 2 || [url.lastPathComponent isEqualToString:@"__MACOSX"]) {
            [enumerator skipDescendants];
            continue;
        }
        [found addObject:url.path];
    }
    [found sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger da = a.pathComponents.count, db = b.pathComponents.count;
        return da != db ? (da < db ? NSOrderedAscending : NSOrderedDescending) : [a localizedStandardCompare:b];
    }];
    for (NSString *path in found) {
        if (isCursorFile(path))
            [cursors addObject:path];
        else if ([path.pathExtension.lowercaseString isEqualToString:@"inf"])
            [infs addObject:path];
    }
}

BOOL MCIsWindowsCursorPath(NSString *path) {
    NSString *extension = path.pathExtension.lowercaseString;
    if (isCursorFile(path) || [extension isEqualToString:@"inf"])
        return YES;

    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] || !directory)
        return NO;
    NSMutableArray *cursors = [NSMutableArray array];
    collectThemeFiles(path, cursors, [NSMutableArray array]);
    return cursors.count > 0;
}

static NSError *windowsError(NSString *reason) {
    return [NSError errorWithDomain:MCErrorDomain code:MCErrorInvalidFormatCode userInfo:@{
        NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cape file", nil),
        NSLocalizedFailureReasonErrorKey: reason }];
}

NSDictionary *createCapeFromWindowsCursors(NSArray *paths, NSDictionary *metadata, NSError **error) {
    NSMutableArray *cursorFiles = [NSMutableArray array], *infs = [NSMutableArray array];
    NSString *folder = nil;
    for (NSString *path in paths) {
        BOOL directory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory])
            continue;
        if (directory) {
            folder = folder ?: path;
            collectThemeFiles(path, cursorFiles, infs);
        } else if ([path.pathExtension.lowercaseString isEqualToString:@"inf"]) {
            // An .inf stands for its whole theme
            folder = folder ?: path.stringByDeletingLastPathComponent;
            [infs insertObject:path atIndex:0];
            collectThemeFiles(path.stringByDeletingLastPathComponent, cursorFiles, [NSMutableArray array]);
        } else if (isCursorFile(path)) {
            folder = folder ?: path.stringByDeletingLastPathComponent;
            [cursorFiles addObject:path];
        }
    }
    if (!cursorFiles.count) {
        if (error)
            *error = windowsError(NSLocalizedString(@"There are no .ani or .cur files here.", nil));
        return nil;
    }

    // A pack can hold several themes (light and dark, say), each with its own .inf. The shallowest
    // one is used, with the cursors beside or below it, so the themes don't get mixed.
    NSArray *candidates = cursorFiles;
    if (infs.count) {
        NSString *infFolder = [[infs[0] stringByDeletingLastPathComponent] stringByAppendingString:@"/"];
        NSArray *beside = [cursorFiles filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@", infFolder]];
        if (beside.count)
            candidates = beside;
    }
    NSMutableDictionary *filesByName = [NSMutableDictionary dictionary];
    for (NSString *file in candidates.reverseObjectEnumerator)
        filesByName[file.lastPathComponent.lowercaseString] = file;

    // Which file is which pointer: the theme's .inf, then the file names
    NSMutableDictionary *roleFiles = [NSMutableDictionary dictionary];
    NSString *schemeName = nil;
    if (infs.count) {
        NSDictionary *roles = rolesFromInf(infs[0], &schemeName);
        for (NSString *role in roles) {
            NSString *file = filesByName[roles[role]];
            if (file)
                roleFiles[role] = file;
        }
    }
    for (NSString *file in candidates) {
        if ([roleFiles.allValues containsObject:file])
            continue;
        NSString *role = roleForFileName(file.lastPathComponent);
        if (role && !roleFiles[role])
            roleFiles[role] = file;
    }
    // A single cursor with a name that says nothing is most likely a pointer
    if (!roleFiles.count && candidates.count == 1)
        roleFiles[@"arrow"] = candidates[0];

    NSMutableDictionary *cursors = [NSMutableDictionary dictionary];
    NSString *title = nil, *artist = nil;
    for (NSString *role in [roleFiles.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray *identifiers = identifiersForRole(role);
        if (!identifiers)
            continue;
        NSDictionary *cursor = cursorFromWindowsFile(roleFiles[role], title ? NULL : &title, artist ? NULL : &artist);
        if (!cursor) {
            MMLog(BOLD YELLOW "Skipped %s: it can't be read" RESET, [roleFiles[role] lastPathComponent].UTF8String);
            continue;
        }
        for (NSString *identifier in identifiers)
            cursors[identifier] = cursor;
    }
    if (!cursors.count) {
        if (error)
            *error = windowsError(NSLocalizedString(@"None of the cursors could be read or matched to a macOS cursor.", nil));
        return nil;
    }

    // Named for the theme; a cursor file on its own goes by its title or file name
    NSString *themeName = schemeName.length ? schemeName : nil;
    if (!themeName && paths.count == 1 && isCursorFile(paths[0]))
        themeName = title.length ? title : [paths[0] lastPathComponent].stringByDeletingPathExtension;
    NSString *name = metadata[@"name"] ?: themeName ?: folder.lastPathComponent;
    NSString *author = metadata[@"author"] ?: artist.length ? artist : NSLocalizedString(@"Unknown", @"Author of an imported cape that doesn't name one");
    NSString *safeName = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]] componentsJoinedByString:@"-"];
    NSString *identifier = metadata[@"identifier"] ?: [NSString stringWithFormat:@"local.import.%@.%f", safeName, [NSDate timeIntervalSinceReferenceDate]];

    NSMutableDictionary *cape = [NSMutableDictionary dictionary];
    [cape setObject:@(MCCursorCreatorVersion) forKey:(id)MCCursorDictionaryVersionKey];
    [cape setObject:@(MCCursorParserVersion) forKey:(id)MCCursorDictionaryMinimumVersionKey];
    [cape setObject:author forKey:(id)MCCursorDictionaryAuthorKey];
    [cape setObject:name forKey:(id)MCCursorDictionaryCapeNameKey];
    [cape setObject:identifier forKey:(id)MCCursorDictionaryIdentifierKey];
    [cape setObject:metadata[@"version"] ?: @1.0 forKey:(id)MCCursorDictionaryCapeVersionKey];
    [cape setObject:@NO forKey:(id)MCCursorDictionaryCloudKey];
    [cape setObject:@YES forKey:(id)MCCursorDictionaryHiDPIKey];
    [cape setObject:cursors forKey:(id)MCCursorDictionaryCursorsKey];
    return cape;
}
