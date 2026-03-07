// mac/OpenLyricsView.h
#pragma once

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

@interface OpenLyricsView : NSView

- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

#endif // __OBJC__
