#import <OakTabBarView/OakTabBarView.h>

extern NSString* const kUserDefaultsProjectSidebarWidthKey;

@interface ProjectLayoutView : NSView
@property (nonatomic) NSView* documentView;
@property (nonatomic) NSView* projectSidebarView;
@property (nonatomic) NSView* fileBrowserView;
@property (nonatomic) NSView* htmlOutputView;

@property (nonatomic) CGFloat projectSidebarWidth;
@property (nonatomic) CGFloat fileBrowserWidth;
@property (nonatomic) BOOL fileBrowserOnRight;

@property (nonatomic) NSSize htmlOutputSize;
@property (nonatomic) BOOL htmlOutputOnRight;
@end
