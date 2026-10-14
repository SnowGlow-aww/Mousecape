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

// The WindowServer refuses to register animations with more frames than this
#define MCMaxFrameCount 24

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

// Registers the cursor under every given name, decoding its images only once
static BOOL applyCapeForIdentifiers(NSDictionary *cursor, NSArray *identifiers, BOOL restore) {
    NSString *identifier = identifiers.firstObject;
    BOOL lefty = MCFlag(MCPreferencesHandednessKey);
    BOOL pointer = MCCursorIsPointer(identifier);
    NSNumber *frameCount    = cursor[MCCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MCCursorDictionaryFrameDuratiomKey];
    //    NSNumber *repeatCount   = cursor[MCCursorDictionaryRepeatCountKey];
    
    CGPoint hotSpot         = CGPointMake([cursor[MCCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MCCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MCCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MCCursorDictionaryPointsHighKey] doubleValue]);
    NSArray *reps           = cursor[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *images  = [NSMutableArray array];

    if (lefty && !restore && pointer) {
        MMLog("Lefty mode for %s", identifier.UTF8String);
        hotSpot.x = size.width - hotSpot.x - 1;
    }

    for (id object in reps) {
        CFTypeID type = CFGetTypeID((__bridge CFTypeRef)object);
        NSBitmapImageRep *rep;
        if (type == CGImageGetTypeID()) {
            rep = [[[NSBitmapImageRep alloc] initWithCGImage:(__bridge CGImageRef)object] autorelease];
        } else {
            rep = [[[NSBitmapImageRep alloc] initWithData:object] autorelease];
        }
        rep = rep.retaggedSRGBSpace;

        if (!lefty || restore || !pointer) {
            // special case if array has a type of CGImage already there is no need to convert it
            if (type == CGImageGetTypeID()) {
                images[images.count] = object;
                continue;
            }
            
            images[images.count] = (__bridge id)[rep CGImage];
            
        } else {
            NSBitmapImageRep *newRep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                               pixelsWide:rep.pixelsWide
                                                                               pixelsHigh:rep.pixelsHigh
                                                                            bitsPerSample:8
                                                                          samplesPerPixel:4
                                                                                 hasAlpha:YES
                                                                                 isPlanar:NO
                                                                           colorSpaceName:NSCalibratedRGBColorSpace
                                                                              bytesPerRow:4 * rep.pixelsWide
                                                                             bitsPerPixel:32] autorelease];
            NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:newRep];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:rep.pixelsWide yBy:0];
            [transform scaleXBy:-1 yBy:1];
            [transform concat];

            [rep drawInRect:NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0
             respectFlipped:NO
                      hints:nil];
            [NSGraphicsContext restoreGraphicsState];
            images[images.count] = (__bridge id)[newRep CGImage];
        }
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
    return applyCapeForIdentifiers(cursor, @[ identifier ], restore);
}

BOOL applyCape(NSDictionary *dictionary) {
    @autoreleasepool {
        NSDictionary *cursors = dictionary[MCCursorDictionaryCursorsKey];
        NSString *name = dictionary[MCCursorDictionaryCapeNameKey];
        NSNumber *version = dictionary[MCCursorDictionaryCapeVersionKey];
        
        resetAllCursors();
        backupAllCursors();
        
        MMLog("Applying cape: %s %.02f", name.UTF8String, version.floatValue);
        
        for (NSString *key in cursors) {
            NSDictionary *cape = cursors[key];
            NSArray *identifiers = @[ key ];

            // Also theme the name newer systems draw this cursor from, unless the cape has its own
            NSString *alias = cursorAliasForIdentifier(key);
            bool aliasRegistered = false;
            if (alias && !cursors[alias])
                MCIsCursorRegistered(CGSMainConnectionID(), (char *)alias.UTF8String, &aliasRegistered);
            if (aliasRegistered)
                identifiers = @[ key, alias ];

            MMLog("Hooking for %s", [identifiers componentsJoinedByString:@", "].UTF8String);

            BOOL success = applyCapeForIdentifiers(cape, identifiers, NO);
            if (!success) {
                MMLog(BOLD RED "Failed to hook identifier %s for some unknown reason. Bailing out..." RESET, key.UTF8String);
                return NO;
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
