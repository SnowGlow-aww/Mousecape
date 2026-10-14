//
//  apply.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "create.h"
#import "backup.h"
#import "restore.h"
#import "MCPrefs.h"
#import "NSBitmapImageRep+ColorSpace.h"

// Copies every step-th frame out of a vertical strip of frameCount frames
static CGImageRef createImageKeepingFrames(CGImageRef image, NSUInteger frameCount, NSUInteger step, NSUInteger keptCount) {
    size_t width = CGImageGetWidth(image);
    size_t frameHeight = CGImageGetHeight(image) / frameCount;

    CGColorSpaceRef space = CGImageGetColorSpace(image);
    CGContextRef ctx = NULL;
    if (space && CGColorSpaceGetModel(space) == kCGColorSpaceModelRGB)
        ctx = CGBitmapContextCreate(NULL, width, frameHeight * keptCount, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!ctx) {
        space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        ctx = CGBitmapContextCreate(NULL, width, frameHeight * keptCount, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
    }
    if (!ctx)
        return NULL;

    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    for (NSUInteger i = 0; i < keptCount; i++) {
        // Image rects count from the top, the context counts from the bottom
        CGImageRef frame = CGImageCreateWithImageInRect(image, CGRectMake(0, i * step * frameHeight, width, frameHeight));
        CGContextDrawImage(ctx, CGRectMake(0, (keptCount - 1 - i) * frameHeight, width, frameHeight), frame);
        CGImageRelease(frame);
    }

    CGImageRef result = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return result;
}

// Draws the image as premultiplied BGRA, which is how the WindowServer keeps cursors. Given any
// other layout, registration converts every pixel itself, one cursor at a time; done here, applyCape
// can spread the work over all cores.
static CGImageRef createCursorImage(CGImageRef image, BOOL mirror) {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!ctx)
        return NULL;

    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    if (mirror) {
        CGContextTranslateCTM(ctx, width, 0);
        CGContextScaleCTM(ctx, -1, 1);
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image);

    CGImageRef result = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return result;
}

BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount) {
    if (frameCount < 1) {
        MMLog(BOLD RED "Frame count of %s out of range [1...%d]" RESET, ident.UTF8String, MCMaxFrameCount);
        return NO;
    }

    if (frameCount > MCMaxFrameCount) {
        // Show every step-th frame for step times as long so the cycle keeps its length. The stock
        // wait cursor on macOS 27 has 30 frames, so without this it could never be backed up.
        NSUInteger step = (frameCount + MCMaxFrameCount - 1) / MCMaxFrameCount;
        NSUInteger keptCount = (frameCount + step - 1) / step;
        NSMutableArray *keptImages = [NSMutableArray arrayWithCapacity:images.count];
        for (id image in images) {
            CGImageRef kept = createImageKeepingFrames((CGImageRef)image, frameCount, step, keptCount);
            if (!kept)
                return NO;
            [keptImages addObject:(id)kept];
            CGImageRelease(kept);
        }

        MMLog("Reduced %s from %lu to %lu frames", ident.UTF8String, (unsigned long)frameCount, (unsigned long)keptCount);
        images = keptImages;
        frameCount = keptCount;
        frameDuration *= step;
    }

    char *idenfifier = (char *)ident.UTF8String;
    int seed = 0;
    CGError err = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                              idenfifier,
                                              true,
                                              true,
                                              size,
                                              hotSpot,
                                              frameCount,
                                              frameDuration,
                                              (__bridge CFArrayRef)images,
                                              &seed);
    
    return (err == kCGErrorSuccess);
}

static BOOL shouldMirrorCursor(NSString *identifier, BOOL restore) {
    return !restore && MCCursorIsPointer(identifier) && MCFlag(MCPreferencesHandednessKey);
}

// The cursor's images ready to register, or nil if one can't be read. Safe to call from any thread.
static NSArray *imagesForCursor(NSDictionary *cursor, BOOL mirror) {
    NSArray *reps = cursor[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:reps.count];

    for (id object in reps) {
        // Backups come straight from the WindowServer, so hand them back untouched
        BOOL fromServer = CFGetTypeID((__bridge CFTypeRef)object) == CGImageGetTypeID();
        if (fromServer && !mirror) {
            [images addObject:object];
            continue;
        }

        CGImageRef image = fromServer ? (CGImageRef)object : [[[[NSBitmapImageRep alloc] initWithData:object] autorelease].retaggedSRGBSpace CGImage];
        CGImageRef converted = image ? createCursorImage(image, mirror) : NULL;
        if (!converted)
            return nil;
        [images addObject:(id)converted];
        CGImageRelease(converted);
    }

    return images;
}

// Registers the prepared images under every given name
static BOOL registerCursor(NSDictionary *cursor, NSArray *images, BOOL mirror, NSArray *identifiers) {
    NSNumber *frameCount    = cursor[MCCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MCCursorDictionaryFrameDuratiomKey];
    //    NSNumber *repeatCount   = cursor[MCCursorDictionaryRepeatCountKey];
    
    CGPoint hotSpot         = CGPointMake([cursor[MCCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MCCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MCCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MCCursorDictionaryPointsHighKey] doubleValue]);

    if (mirror) {
        MMLog("Lefty mode for %s", [identifiers.firstObject UTF8String]);
        hotSpot.x = size.width - hotSpot.x - 1;
    }

    for (NSString *name in identifiers) {
        if (!applyCursorForIdentifier(frameCount.unsignedIntegerValue, frameDuration.doubleValue, hotSpot, size, images, name, 0))
            return NO;
    }
    return YES;
}

BOOL applyCapeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore) {
    if (!cursor || !identifier) {
        NSLog(@"bad seed");
        return NO;
    }

    BOOL mirror = shouldMirrorCursor(identifier, restore);
    NSArray *images = imagesForCursor(cursor, mirror);
    return images && registerCursor(cursor, images, mirror, @[ identifier ]);
}

// Checked before anything is reset, so a cape that can't be applied leaves the current cursors
// alone. Applying one with an empty cursor used to reset everything and then stop partway.
static BOOL capeCanBeApplied(NSDictionary *cursors) {
    if (![cursors isKindOfClass:[NSDictionary class]] || cursors.count == 0) {
        MMLog(BOLD RED "This cape has no cursors" RESET);
        return NO;
    }

    for (NSString *key in cursors) {
        NSDictionary *cursor = cursors[key];
        NSArray *reps = [cursor isKindOfClass:[NSDictionary class]] ? cursor[MCCursorDictionaryRepresentationsKey] : nil;
        if (![reps isKindOfClass:[NSArray class]] || reps.count == 0 ||
            [cursor[MCCursorDictionaryFrameCountKey] integerValue] < 1 ||
            [cursor[MCCursorDictionaryPointsWideKey] doubleValue] <= 0 ||
            [cursor[MCCursorDictionaryPointsHighKey] doubleValue] <= 0) {
            MMLog(BOLD RED "Cursor %s has no images or no size" RESET, key.UTF8String);
            return NO;
        }
    }
    return YES;
}

BOOL applyCape(NSDictionary *dictionary) {
    @autoreleasepool {
        NSDictionary *cursors = dictionary[MCCursorDictionaryCursorsKey];
        NSString *name = dictionary[MCCursorDictionaryCapeNameKey];
        NSNumber *version = dictionary[MCCursorDictionaryCapeVersionKey];
        
        if (!capeCanBeApplied(cursors)) {
            MMLog(BOLD RED "Not applying %s; the current cursors are unchanged." RESET, name.UTF8String);
            return NO;
        }
        
        resetAllCursors();
        backupAllCursors();
        
        MMLog("Applying cape: %s %.02f", name.UTF8String, version.floatValue);
        
        NSArray *keys = cursors.allKeys;
        NSUInteger batchSize = NSProcessInfo.processInfo.activeProcessorCount;
        for (NSUInteger start = 0; start < keys.count; start += batchSize) @autoreleasepool {
            NSArray *batch = [keys subarrayWithRange:NSMakeRange(start, MIN(batchSize, keys.count - start))];
            NSMutableArray *prepared = [NSMutableArray arrayWithCapacity:batch.count];
            for (NSUInteger i = 0; i < batch.count; i++)
                [prepared addObject:[NSNull null]];

            // Decoding the images is most of the work and each cursor's are independent, so spread
            // them over the cores. Going in batches keeps only a few cursors' pixels in memory.
            dispatch_apply(batch.count, DISPATCH_APPLY_AUTO, ^(size_t i) {
                @autoreleasepool {
                    NSString *key = batch[i];
                    NSArray *images = imagesForCursor(cursors[key], shouldMirrorCursor(key, NO));
                    if (images) {
                        @synchronized (prepared) {
                            prepared[i] = images;
                        }
                    }
                }
            });

            for (NSUInteger i = 0; i < batch.count; i++) {
                NSString *key = batch[i];
                NSArray *identifiers = @[ key ];

                // Also theme the name newer systems draw this cursor from, unless the cape has its own
                NSString *alias = cursorAliasForIdentifier(key);
                bool aliasRegistered = false;
                if (alias && !cursors[alias])
                    MCIsCursorRegistered(CGSMainConnectionID(), (char *)alias.UTF8String, &aliasRegistered);
                if (aliasRegistered)
                    identifiers = @[ key, alias ];

                MMLog("Hooking for %s", [identifiers componentsJoinedByString:@", "].UTF8String);

                NSArray *images = prepared[i];
                BOOL success = images != (id)[NSNull null] && registerCursor(cursors[key], images, shouldMirrorCursor(key, NO), identifiers);
                if (!success) {
                    MMLog(BOLD RED "Failed to hook identifier %s for some unknown reason. Bailing out..." RESET, key.UTF8String);
                    // Go back to the default cursors rather than leave half a cape applied
                    resetAllCursors();
                    return NO;
                }
            }
        }
        
        MCSetDefault(dictionary[MCCursorDictionaryIdentifierKey], MCPreferencesAppliedCursorKey);
        
        MMLog(BOLD GREEN "Applied %s successfully!" RESET, name.UTF8String);
        
        return YES;
    }
}

BOOL applyCapeAtPath(NSString *path) {
    NSDictionary *cape = [NSDictionary dictionaryWithContentsOfFile:path];
    if (cape)
        return applyCape(cape);
    MMLog(BOLD RED "Could not find valid file at %s to apply" RESET, path.UTF8String);
    return NO;
}
