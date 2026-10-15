#import <Cocoa/Cocoa.h>

@class ProjectSidebarViewController;

@protocol ProjectSidebarDelegate <NSObject>
- (void)projectSidebar:(ProjectSidebarViewController*)sidebar openURL:(NSURL*)url;
@optional
- (void)projectSidebar:(ProjectSidebarViewController*)sidebar didMoveURL:(NSURL*)fromURL toURL:(NSURL*)toURL;
@end

@interface ProjectSidebarViewController : NSViewController
@property (nonatomic, weak) id <ProjectSidebarDelegate> delegate;
- (void)reloadContents;
- (void)revealPath:(NSString*)path;
- (void)setContentTopInset:(CGFloat)inset;
@end
