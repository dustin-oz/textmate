#import <Cocoa/Cocoa.h>

@class ProjectSidebarViewController;

@protocol ProjectSidebarDelegate <NSObject>
- (void)projectSidebar:(ProjectSidebarViewController*)sidebar openURL:(NSURL*)url;
@end

@interface ProjectSidebarViewController : NSViewController
@property (nonatomic, weak) id <ProjectSidebarDelegate> delegate;
- (void)reloadContents;
- (void)setContentTopInset:(CGFloat)inset;
@end
