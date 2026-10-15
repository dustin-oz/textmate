#import "ProjectSidebarViewController.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString* const ProjectSidebarFoldersKey = @"projectSidebarFolders";
static NSString* const ProjectSidebarFoldersDidChangeNotification = @"ProjectSidebarFoldersDidChangeNotification";
static NSString* const ProjectSidebarDragType = @"com.macromates.TextMate.projectSidebarFolder";

@interface ProjectSidebarNode : NSObject
@property (nonatomic) NSURL* url;
@property (nonatomic) NSString* name;
@property (nonatomic) BOOL directory;
@property (nonatomic) BOOL missing;
@property (nonatomic) NSArray<ProjectSidebarNode*>* children;
@property (nonatomic, weak) ProjectSidebarNode* parent;
@end

@implementation ProjectSidebarNode
@end

@interface ProjectSidebarCellView : NSView
@property (nonatomic) NSImageView* iconView;
@property (nonatomic) NSTextField* nameField;
@end

@implementation ProjectSidebarCellView
- (instancetype)initWithFrame:(NSRect)frame
{
	if((self = [super initWithFrame:frame]))
	{
		_iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		_iconView.translatesAutoresizingMaskIntoConstraints = NO;
		_iconView.imageScaling = NSImageScaleProportionallyDown;
		_nameField = [NSTextField labelWithString:@""];
		_nameField.translatesAutoresizingMaskIntoConstraints = NO;
		_nameField.lineBreakMode = NSLineBreakByTruncatingMiddle;
		[_nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self addSubview:_iconView];
		[self addSubview:_nameField];
		NSArray<NSLayoutConstraint*>* constraints = @[
			[_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
			[_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
			[_iconView.widthAnchor constraintEqualToConstant:16],
			[_iconView.heightAnchor constraintEqualToConstant:16],
			[_nameField.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:4],
			[_nameField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
			[_nameField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
		];
		for(NSLayoutConstraint* constraint in constraints)
			constraint.priority = NSLayoutPriorityDefaultHigh;
		[NSLayoutConstraint activateConstraints:constraints];
	}
	return self;
}
@end

@interface ProjectSidebarOutlineView : NSOutlineView
@end

@implementation ProjectSidebarOutlineView
- (void)keyDown:(NSEvent*)event
{
	NSString* chars = event.charactersIgnoringModifiers;
	if([chars isEqualToString:@"\x7F"] || [chars isEqualToString:@"\uF728"])
	{
		if([NSApp sendAction:@selector(delete:) to:nil from:self])
			return;
	}
	[super keyDown:event];
}
@end

static NSArray<NSString*>* ProjectSidebarFolderPaths ()
{
	NSArray* paths = [NSUserDefaults.standardUserDefaults arrayForKey:ProjectSidebarFoldersKey];
	return [paths isKindOfClass:NSArray.class] ? paths : @[];
}

static void ProjectSidebarSetFolderPaths (NSArray<NSString*>* paths)
{
	[NSUserDefaults.standardUserDefaults setObject:paths forKey:ProjectSidebarFoldersKey];
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:ProjectSidebarFoldersDidChangeNotification object:nil];
	});
}

static BOOL ProjectSidebarFileIsViewable (NSURL* url)
{
	NSString* ext = url.pathExtension.lowercaseString;
	static NSSet<NSString*>* extra = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		extra = [NSSet setWithObjects:
			@"md", @"markdown", @"mdown", @"mkd", @"txt", @"text",
			@"html", @"htm", @"css", @"scss", @"less",
			@"js", @"jsx", @"mjs", @"cjs", @"ts", @"tsx",
			@"json", @"yaml", @"yml", @"toml", @"xml", @"plist",
			@"csv", @"tsv", @"rst", @"org", @"adoc", @"asciidoc",
			@"sh", @"bash", @"zsh", @"py", @"rb", @"php", @"go", @"rs",
			@"java", @"kt", @"c", @"cc", @"cpp", @"cxx", @"h", @"hh", @"hpp",
			@"m", @"mm", @"swift", @"cmake", @"ini", @"conf", @"cfg", @"log",
			@"sql", @"tex", @"lua", @"pl", @"vue", @"svelte", nil];
	});
	if([extra containsObject:ext])
		return YES;

	if(ext.length)
	{
		UTType* type = [UTType typeWithFilenameExtension:ext];
		if(type && ([type conformsToType:UTTypePlainText] || [type conformsToType:UTTypeSourceCode] || [type conformsToType:UTTypeText] || [type conformsToType:UTTypeJSON] || [type conformsToType:UTTypeXML] || [type conformsToType:UTTypePropertyList]))
			return YES;
		return NO;
	}

	NSFileHandle* handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
	if(!handle)
		return NO;
	NSData* data = [handle readDataOfLength:512];
	[handle closeFile];
	if(data.length == 0)
		return YES;
	const unsigned char* bytes = (const unsigned char*)data.bytes;
	for(NSUInteger i = 0; i < data.length; ++i)
	{
		if(bytes[i] == 0)
			return NO;
	}
	return YES;
}

static BOOL ProjectSidebarShouldSkipDirectory (NSString* name)
{
	static NSSet<NSString*>* skip = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		skip = [NSSet setWithObjects:@"node_modules", @"Pods", nil];
	});
	return [skip containsObject:name];
}

@interface ProjectSidebarViewController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation>
@property (nonatomic) NSOutlineView* outlineView;
@property (nonatomic) NSTextField* emptyLabel;
@property (nonatomic) NSMutableArray<ProjectSidebarNode*>* roots;
@property (nonatomic) NSArray<NSString*>* pendingExpand;
@property (nonatomic) BOOL suppressOpen;
@property (nonatomic) BOOL reorderDragActive;
@property (nonatomic) NSLayoutConstraint* contentTopConstraint;
@end

@implementation ProjectSidebarViewController

- (void)loadView
{
	NSVisualEffectView* background = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	background.material = NSVisualEffectMaterialSidebar;
	background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
	background.state = NSVisualEffectStateFollowsWindowActiveState;
	self.view = background;

	NSTextField* title = OakCreateLabel(@"Projects", [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold]);
	NSImageSymbolConfiguration* symbol = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
	NSImage* addImage = [NSImage imageWithSystemSymbolName:@"folder.badge.plus" accessibilityDescription:@"Add Folder"];
	addImage = [addImage imageWithSymbolConfiguration:symbol] ?: addImage;
	NSButton* addButton = [NSButton buttonWithImage:addImage target:self action:@selector(addFolder:)];
	addButton.bezelStyle = NSBezelStyleInline;
	addButton.bordered = NO;
	addButton.toolTip = @"Add Folder";

	NSView* header = [[NSView alloc] initWithFrame:NSZeroRect];
	NSBox* separator = [[NSBox alloc] initWithFrame:NSZeroRect];
	separator.boxType = NSBoxSeparator;
	separator.translatesAutoresizingMaskIntoConstraints = NO;

	self.outlineView = [[ProjectSidebarOutlineView alloc] initWithFrame:NSZeroRect];
	self.outlineView.dataSource = self;
	self.outlineView.delegate = self;
	self.outlineView.headerView = nil;
	self.outlineView.allowsMultipleSelection = NO;
	self.outlineView.allowsEmptySelection = YES;
	self.outlineView.rowSizeStyle = NSTableViewRowSizeStyleSmall;
	self.outlineView.rowHeight = 22;
	self.outlineView.style = NSTableViewStyleSourceList;
	self.outlineView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleGap;
	self.outlineView.verticalMotionCanBeginDrag = YES;
	self.outlineView.backgroundColor = NSColor.clearColor;
	self.outlineView.floatsGroupRows = NO;
	self.outlineView.target = self;
	self.outlineView.action = @selector(outlineClicked:);
	self.outlineView.menu = [self contextMenu];
	[self.outlineView registerForDraggedTypes:@[ ProjectSidebarDragType ]];
	[self.outlineView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

	NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	column.resizingMask = NSTableColumnAutoresizingMask;
	[self.outlineView addTableColumn:column];
	self.outlineView.outlineTableColumn = column;

	NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scrollView.documentView = self.outlineView;
	scrollView.hasVerticalScroller = YES;
	scrollView.hasHorizontalScroller = NO;
	scrollView.drawsBackground = NO;
	scrollView.autohidesScrollers = YES;

	self.emptyLabel = OakCreateLabel(@"Add a project folder", [NSFont systemFontOfSize:NSFont.smallSystemFontSize], NSTextAlignmentCenter, NSLineBreakByWordWrapping);
	self.emptyLabel.textColor = NSColor.secondaryLabelColor;

	title.translatesAutoresizingMaskIntoConstraints = NO;
	addButton.translatesAutoresizingMaskIntoConstraints = NO;
	OakAddAutoLayoutViewsToSuperview(@[ header, separator, scrollView, self.emptyLabel ], background);
	[header addSubview:title];
	[header addSubview:addButton];

	NSDictionary* views = @{
		@"header": header,
		@"title": title,
		@"add": addButton,
		@"separator": separator,
		@"scroll": scrollView,
		@"empty": self.emptyLabel,
	};
	[background addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[header]|" options:0 metrics:nil views:views]];
	[background addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[separator]|" options:0 metrics:nil views:views]];
	[background addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[scroll]|" options:0 metrics:nil views:views]];
	self.contentTopConstraint = [header.topAnchor constraintEqualToAnchor:background.topAnchor];
	[NSLayoutConstraint activateConstraints:@[
		self.contentTopConstraint,
		[header.heightAnchor constraintEqualToConstant:32],
		[separator.topAnchor constraintEqualToAnchor:header.bottomAnchor],
		[separator.heightAnchor constraintEqualToConstant:1],
		[scrollView.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
		[scrollView.bottomAnchor constraintEqualToAnchor:background.bottomAnchor],
	]];
	[header addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[title]-(>=4)-[add(24)]-6-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[header addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[title]|" options:0 metrics:nil views:views]];
	[addButton addConstraint:[NSLayoutConstraint constraintWithItem:addButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:24]];
	[background addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-12-[empty]-12-|" options:0 metrics:nil views:views]];
	[background addConstraint:[NSLayoutConstraint constraintWithItem:self.emptyLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

	self.roots = [NSMutableArray array];
	[self reloadFromStore];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foldersDidChange:) name:ProjectSidebarFoldersDidChangeNotification object:nil];
}

- (void)setContentTopInset:(CGFloat)inset
{
	if(fabs(self.contentTopConstraint.constant - inset) < 0.5)
		return;
	self.contentTopConstraint.constant = MAX(0, inset);
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSMenu*)contextMenu
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
	NSMenuItem* reveal = [[NSMenuItem alloc] initWithTitle:@"Reveal in Finder" action:@selector(revealInFinder:) keyEquivalent:@""];
	reveal.target = self;
	[menu addItem:reveal];
	[menu addItem:[NSMenuItem separatorItem]];
	NSMenuItem* remove = [[NSMenuItem alloc] initWithTitle:@"Remove from Sidebar" action:@selector(removeFromSidebar:) keyEquivalent:@""];
	remove.target = self;
	[menu addItem:remove];
	return menu;
}

- (void)foldersDidChange:(NSNotification*)notification
{
	[self reloadFromStore];
}

- (void)reloadContents
{
	[self reloadFromStore];
}

- (void)reloadFromStore
{
	NSArray<NSString*>* expanded = [self expandedPaths];
	NSString* selected = [self selectedPath];
	[self.roots removeAllObjects];
	for(NSString* path in ProjectSidebarFolderPaths())
	{
		if(![path isKindOfClass:NSString.class] || path.length == 0)
			continue;
		[self.roots addObject:[self rootNodeForPath:path.stringByStandardizingPath]];
	}
	self.emptyLabel.hidden = self.roots.count > 0;
	self.suppressOpen = YES;
	[self.outlineView reloadData];
	for(NSString* path in expanded)
	{
		ProjectSidebarNode* node = [self nodeForPath:path];
		if(node.directory)
			[self.outlineView expandItem:node];
	}
	for(NSString* path in self.pendingExpand)
	{
		ProjectSidebarNode* node = [self nodeForPath:path];
		if(node)
			[self.outlineView expandItem:node];
	}
	self.pendingExpand = nil;
	if(selected)
	{
		ProjectSidebarNode* node = [self nodeForPath:selected];
		NSInteger row = node ? [self.outlineView rowForItem:node] : -1;
		if(row >= 0)
			[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	}
	self.suppressOpen = NO;
}

- (ProjectSidebarNode*)rootNodeForPath:(NSString*)path
{
	ProjectSidebarNode* node = [[ProjectSidebarNode alloc] init];
	node.url = [NSURL fileURLWithPath:path];
	node.name = path.lastPathComponent;
	node.directory = YES;
	node.missing = ![NSFileManager.defaultManager fileExistsAtPath:path];
	return node;
}

- (NSArray<NSString*>*)expandedPaths
{
	NSMutableArray* paths = [NSMutableArray array];
	for(NSInteger row = 0; row < self.outlineView.numberOfRows; ++row)
	{
		ProjectSidebarNode* node = [self.outlineView itemAtRow:row];
		if([self.outlineView isItemExpanded:node])
			[paths addObject:node.url.path];
	}
	return paths;
}

- (NSString*)selectedPath
{
	NSInteger row = self.outlineView.selectedRow;
	if(row < 0)
		return nil;
	ProjectSidebarNode* node = [self.outlineView itemAtRow:row];
	return node.url.path;
}

- (ProjectSidebarNode*)nodeForPath:(NSString*)path
{
	for(ProjectSidebarNode* root in self.roots)
	{
		ProjectSidebarNode* found = [self findPath:path inNode:root];
		if(found)
			return found;
	}
	return nil;
}

- (ProjectSidebarNode*)findPath:(NSString*)path inNode:(ProjectSidebarNode*)node
{
	if([node.url.path isEqualToString:path])
		return node;
	for(ProjectSidebarNode* child in node.children)
	{
		ProjectSidebarNode* found = [self findPath:path inNode:child];
		if(found)
			return found;
	}
	return nil;
}

- (NSArray<ProjectSidebarNode*>*)loadChildrenOfNode:(ProjectSidebarNode*)node
{
	if(node.children)
		return node.children;

	NSArray* keys = @[ NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLLocalizedNameKey ];
	NSArray<NSURL*>* urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:node.url includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
	NSMutableArray<ProjectSidebarNode*>* children = [NSMutableArray array];
	for(NSURL* url in urls)
	{
		NSNumber* isDirectory = nil;
		NSNumber* isPackage = nil;
		[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
		[url getResourceValue:&isPackage forKey:NSURLIsPackageKey error:nil];
		NSString* name = nil;
		[url getResourceValue:&name forKey:NSURLLocalizedNameKey error:nil];
		if(name.length == 0)
			name = url.lastPathComponent;

		BOOL directory = isDirectory.boolValue && !isPackage.boolValue;
		if(directory)
		{
			if(ProjectSidebarShouldSkipDirectory(url.lastPathComponent))
				continue;
		}
		else if(!ProjectSidebarFileIsViewable(url))
		{
			continue;
		}

		ProjectSidebarNode* child = [[ProjectSidebarNode alloc] init];
		child.url = url;
		child.name = name;
		child.directory = directory;
		child.parent = node;
		[children addObject:child];
	}

	[children sortUsingComparator:^NSComparisonResult(ProjectSidebarNode* lhs, ProjectSidebarNode* rhs){
		if(lhs.directory != rhs.directory)
			return lhs.directory ? NSOrderedAscending : NSOrderedDescending;
		return [lhs.name localizedStandardCompare:rhs.name];
	}];
	node.children = children;
	return children;
}

- (ProjectSidebarNode*)rootNodeForRow:(NSInteger)row
{
	if(row < 0 || row >= self.outlineView.numberOfRows)
		return nil;
	ProjectSidebarNode* node = [self.outlineView itemAtRow:row];
	return node.parent ? nil : node;
}

- (IBAction)addFolder:(id)sender
{
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = NO;
	panel.canChooseDirectories = YES;
	panel.allowsMultipleSelection = YES;
	panel.prompt = @"Add";
	panel.message = @"Choose a project or folder to keep in the sidebar.";
	[panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result){
		if(result != NSModalResponseOK)
			return;

		NSMutableArray<NSString*>* paths = [ProjectSidebarFolderPaths() mutableCopy];
		NSMutableArray<NSString*>* added = [NSMutableArray array];
		for(NSURL* url in panel.URLs)
		{
			NSString* path = url.path.stringByStandardizingPath;
			if(path.length == 0 || [paths containsObject:path])
				continue;
			[paths addObject:path];
			[added addObject:path];
		}
		if(added.count == 0)
			return;
		self.pendingExpand = added;
		ProjectSidebarSetFolderPaths(paths);
	}];
}

- (ProjectSidebarNode*)nodeForClickedOrSelectedRow
{
	NSInteger row = self.outlineView.clickedRow;
	if(row < 0)
		row = self.outlineView.selectedRow;
	if(row < 0 || row >= self.outlineView.numberOfRows)
		return nil;
	return [self.outlineView itemAtRow:row];
}

- (IBAction)revealInFinder:(id)sender
{
	ProjectSidebarNode* node = [self nodeForClickedOrSelectedRow];
	if(node.url)
		[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ node.url ]];
}

- (IBAction)removeFromSidebar:(id)sender
{
	NSInteger row = self.outlineView.clickedRow;
	if(row < 0)
		row = self.outlineView.selectedRow;
	ProjectSidebarNode* node = [self rootNodeForRow:row];
	if(!node)
		return;

	NSMutableArray<NSString*>* paths = [ProjectSidebarFolderPaths() mutableCopy];
	[paths removeObject:node.url.path];
	ProjectSidebarSetFolderPaths(paths);
}

- (IBAction)delete:(id)sender
{
	[self removeFromSidebar:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem
{
	if(menuItem.action == @selector(revealInFinder:))
		return [self nodeForClickedOrSelectedRow].url != nil;
	if(menuItem.action == @selector(removeFromSidebar:))
	{
		NSInteger row = self.outlineView.clickedRow;
		if(row < 0)
			row = self.outlineView.selectedRow;
		return [self rootNodeForRow:row] != nil;
	}
	return YES;
}

- (void)outlineClicked:(id)sender
{
	if(self.suppressOpen)
		return;

	NSInteger row = self.outlineView.clickedRow;
	if(row < 0 && NSApp.currentEvent.type == NSEventTypeKeyDown)
		row = self.outlineView.selectedRow;
	ProjectSidebarNode* node = row >= 0 ? [self.outlineView itemAtRow:row] : nil;
	if(!node)
		return;

	NSEvent* event = NSApp.currentEvent;
	if(event.window == self.view.window)
	{
		NSPoint point = [self.outlineView convertPoint:event.locationInWindow fromView:nil];
		if(NSPointInRect(point, [self.outlineView frameOfOutlineCellAtRow:row]))
			return;
	}

	if(node.directory)
	{
		if([self.outlineView isItemExpanded:node])
			[self.outlineView collapseItem:node];
		else
			[self.outlineView expandItem:node];
		return;
	}

	[self.delegate projectSidebar:self openURL:node.url];
}

- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item
{
	if(!item)
		return self.roots.count;
	return [self loadChildrenOfNode:item].count;
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item
{
	NSArray<ProjectSidebarNode*>* children = item ? [self loadChildrenOfNode:item] : self.roots;
	return children[index];
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item
{
	return ((ProjectSidebarNode*)item).directory;
}

- (NSView*)outlineView:(NSOutlineView*)outlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item
{
	ProjectSidebarNode* node = item;
	ProjectSidebarCellView* cell = [outlineView makeViewWithIdentifier:@"ProjectCell" owner:self];
	if(!cell)
	{
		cell = [[ProjectSidebarCellView alloc] initWithFrame:NSZeroRect];
		cell.identifier = @"ProjectCell";
	}

	cell.nameField.stringValue = node.name ?: @"";
	cell.nameField.font = node.parent ? [NSFont systemFontOfSize:NSFont.smallSystemFontSize] : [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
	cell.nameField.textColor = node.missing ? NSColor.secondaryLabelColor : NSColor.labelColor;
	cell.iconView.image = [NSWorkspace.sharedWorkspace iconForFile:node.url.path];
	cell.toolTip = node.parent ? nil : node.url.path;
	return cell;
}

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView*)outlineView pasteboardWriterForItem:(id)item
{
	ProjectSidebarNode* node = item;
	if(node.parent)
		return nil;
	NSPasteboardItem* pasteboardItem = [[NSPasteboardItem alloc] init];
	[pasteboardItem setString:node.url.path forType:ProjectSidebarDragType];
	return pasteboardItem;
}

- (void)outlineView:(NSOutlineView*)outlineView draggingSession:(NSDraggingSession*)session willBeginAtPoint:(NSPoint)screenPoint forItems:(NSArray*)draggedItems
{
	self.reorderDragActive = YES;
}

- (void)outlineView:(NSOutlineView*)outlineView draggingSession:(NSDraggingSession*)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation
{
	self.reorderDragActive = NO;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldExpandItem:(id)item
{
	return !self.reorderDragActive;
}

// The whole block for a project, including its open contents, is one reorder target.
// The top half inserts above that project. The bottom half inserts below it.
- (NSInteger)rootInsertionIndexForPoint:(NSPoint)point
{
	NSInteger count = (NSInteger)self.roots.count;
	for(NSInteger index = 0; index < count; ++index)
	{
		NSInteger headerRow = [self.outlineView rowForItem:self.roots[index]];
		if(headerRow < 0)
			continue;

		NSInteger endRow = headerRow;
		if(index + 1 < count)
		{
			NSInteger nextHeader = [self.outlineView rowForItem:self.roots[index + 1]];
			if(nextHeader > headerRow)
				endRow = nextHeader - 1;
		}
		else
		{
			endRow = self.outlineView.numberOfRows - 1;
		}

		NSRect top = [self.outlineView rectOfRow:headerRow];
		NSRect bottom = [self.outlineView rectOfRow:endRow];
		if(point.y < (NSMinY(top) + NSMaxY(bottom)) / 2.0)
			return index;
	}
	return count;
}

- (NSDragOperation)outlineView:(NSOutlineView*)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
	if(![[info.draggingPasteboard types] containsObject:ProjectSidebarDragType])
		return NSDragOperationNone;

	NSPoint point = [outlineView convertPoint:info.draggingLocation fromView:nil];
	NSInteger insertion = [self rootInsertionIndexForPoint:point];
	if(item != nil || index != insertion)
		[outlineView setDropItem:nil dropChildIndex:insertion];
	return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
	NSMutableArray<NSString*>* moving = [NSMutableArray array];
	[info enumerateDraggingItemsWithOptions:0 forView:outlineView classes:@[ NSPasteboardItem.class ] searchOptions:@{} usingBlock:^(NSDraggingItem* draggingItem, NSInteger idx, BOOL* stop){
		NSString* path = [((NSPasteboardItem*)draggingItem.item) stringForType:ProjectSidebarDragType];
		if(path)
			[moving addObject:path];
	}];
	if(moving.count == 0)
	{
		NSString* path = [info.draggingPasteboard stringForType:ProjectSidebarDragType];
		if(path.length)
			[moving addObject:path];
	}
	if(moving.count == 0 || item != nil)
		return NO;

	NSMutableArray<NSString*>* paths = [ProjectSidebarFolderPaths() mutableCopy];
	NSInteger insert = index;
	for(NSString* path in moving)
	{
		NSUInteger old = [paths indexOfObject:path];
		if(old == NSNotFound)
			continue;
		[paths removeObjectAtIndex:old];
		if((NSInteger)old < insert)
			--insert;
	}
	insert = MAX(0, MIN(insert, (NSInteger)paths.count));
	for(NSString* path in moving)
		[paths insertObject:path atIndex:insert++];
	if(![paths isEqualToArray:ProjectSidebarFolderPaths()])
		ProjectSidebarSetFolderPaths(paths);
	return YES;
}

@end
