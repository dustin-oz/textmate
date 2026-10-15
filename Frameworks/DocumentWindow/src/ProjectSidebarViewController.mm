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

@interface ProjectSidebarCellView : NSTableCellView
@end

@implementation ProjectSidebarCellView
- (instancetype)initWithFrame:(NSRect)frame
{
	if((self = [super initWithFrame:frame]))
	{
		NSImageView* iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		iconView.translatesAutoresizingMaskIntoConstraints = NO;
		iconView.imageScaling = NSImageScaleProportionallyDown;
		NSTextField* nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
		nameField.translatesAutoresizingMaskIntoConstraints = NO;
		nameField.bezeled = NO;
		nameField.drawsBackground = NO;
		nameField.editable = YES;
		nameField.selectable = YES;
		nameField.lineBreakMode = NSLineBreakByTruncatingMiddle;
		nameField.usesSingleLineMode = YES;
		nameField.cell.scrollable = NO;
		[nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		[nameField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		self.imageView = iconView;
		self.textField = nameField;
		[self addSubview:iconView];
		[self addSubview:nameField];
		// The icon position has to win. A long name used to break a weaker
		// leading constraint and slide the icon left, so the rows looked nested.
		NSLayoutConstraint* iconLeading = [iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2];
		NSLayoutConstraint* textTrailing = [nameField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4];
		textTrailing.priority = NSLayoutPriorityDefaultHigh;
		[NSLayoutConstraint activateConstraints:@[
			iconLeading,
			[iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
			[iconView.widthAnchor constraintEqualToConstant:16],
			[iconView.heightAnchor constraintEqualToConstant:16],
			[nameField.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:4],
			[nameField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
			textTrailing,
		]];
	}
	return self;
}
@end

@interface ProjectSidebarOutlineView : NSOutlineView
@end

@implementation ProjectSidebarOutlineView
// A top-level file has no disclosure triangle, so the source list shifts it
// right until it looks like a child of the project above it. Match the cell
// of an expandable sibling at the same level instead.
- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
	NSRect frame = [super frameOfCellAtColumn:column row:row];
	if(column != 0)
		return frame;

	id item = [self itemAtRow:row];
	if(!item || [self isExpandable:item])
		return frame;

	id parent = [self parentForItem:item];
	for(NSInteger other = 0; other < self.numberOfRows; ++other)
	{
		if(other == row)
			continue;
		id sibling = [self itemAtRow:other];
		if(!sibling || ![self isExpandable:sibling] || [self parentForItem:sibling] != parent)
			continue;

		NSRect siblingFrame = [super frameOfCellAtColumn:column row:other];
		CGFloat shift = frame.origin.x - siblingFrame.origin.x;
		if(shift > 0.5)
		{
			frame.origin.x -= shift;
			frame.size.width += shift;
		}
		break;
	}
	return frame;
}

- (void)setFrameSize:(NSSize)newSize
{
	NSSize visible = self.enclosingScrollView.contentView.bounds.size;
	if(newSize.height < visible.height)
		newSize.height = visible.height;
	[super setFrameSize:newSize];
}

- (void)mouseDown:(NSEvent*)event
{
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	if([self rowAtPoint:point] < 0)
		[self deselectAll:nil];
	else
		[super mouseDown:event];
}

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

static NSURL* ProjectSidebarUniqueURL (NSURL* directory, NSString* baseName, NSString* pathExtension, BOOL isDirectory)
{
	NSFileManager* fileManager = NSFileManager.defaultManager;
	for(NSUInteger index = 1; index < 1000; ++index)
	{
		NSString* name = index == 1 ? baseName : [NSString stringWithFormat:@"%@ %lu", baseName, (unsigned long)index];
		if(pathExtension.length)
			name = [name stringByAppendingPathExtension:pathExtension];
		NSURL* url = [directory URLByAppendingPathComponent:name isDirectory:isDirectory];
		if(![fileManager fileExistsAtPath:url.path])
			return url;
	}
	return nil;
}

@interface ProjectSidebarViewController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation, NSOpenSavePanelDelegate, NSTextFieldDelegate>
@property (nonatomic) NSOutlineView* outlineView;
@property (nonatomic) NSTextField* emptyLabel;
@property (nonatomic) NSMutableArray<ProjectSidebarNode*>* roots;
@property (nonatomic) NSArray<NSString*>* pendingExpand;
@property (nonatomic) NSString* pendingSelectPath;
@property (nonatomic) NSString* pendingRenamePath;
@property (nonatomic) NSURL* createdItemURL;
@property (nonatomic) BOOL createdItemOpens;
@property (nonatomic) BOOL preparedForRename;
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
	title.lineBreakMode = NSLineBreakByTruncatingTail;
	[title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	NSButton* addButton = [self headerButtonWithSymbol:@"folder.badge.plus" action:@selector(addFolder:) tooltip:@"Add Existing Folder"];
	NSButton* newFolderButton = [self headerButtonWithSymbol:@"folder.fill.badge.plus" action:@selector(newFolder:) tooltip:@"New Folder"];
	NSButton* newFileButton = [self headerButtonWithSymbol:@"doc.badge.plus" action:@selector(newFile:) tooltip:@"New File"];

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
	[self.outlineView registerForDraggedTypes:@[ ProjectSidebarDragType, NSPasteboardTypeFileURL ]];
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
	OakAddAutoLayoutViewsToSuperview(@[ header, separator, self.emptyLabel, scrollView ], background);
	[header addSubview:title];
	[header addSubview:addButton];
	[header addSubview:newFolderButton];
	[header addSubview:newFileButton];

	NSDictionary* views = @{
		@"header": header,
		@"title": title,
		@"add": addButton,
		@"newFolder": newFolderButton,
		@"newFile": newFileButton,
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
	[header addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[title]-(>=4)-[add(24)]-4-[newFolder(24)]-4-[newFile(24)]-6-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[header addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[title]|" options:0 metrics:nil views:views]];
	for(NSButton* button in @[ addButton, newFolderButton, newFileButton ])
		[button addConstraint:[NSLayoutConstraint constraintWithItem:button attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:24]];
	[background addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-12-[empty]-12-|" options:0 metrics:nil views:views]];
	[background addConstraint:[NSLayoutConstraint constraintWithItem:self.emptyLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

	self.roots = [NSMutableArray array];
	[self reloadFromStore];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foldersDidChange:) name:ProjectSidebarFoldersDidChangeNotification object:nil];
}

- (ProjectSidebarNode*)rootContainingPath:(NSString*)path
{
	ProjectSidebarNode* best = nil;
	NSUInteger bestLength = 0;
	for(ProjectSidebarNode* root in self.roots)
	{
		NSString* rootPath = root.url.path.stringByStandardizingPath;
		BOOL contains = [path isEqualToString:rootPath];
		if(!contains)
		{
			NSString* prefix = [rootPath hasSuffix:@"/"] ? rootPath : [rootPath stringByAppendingString:@"/"];
			contains = [path hasPrefix:prefix];
		}
		if(contains && rootPath.length >= bestLength)
		{
			best = root;
			bestLength = rootPath.length;
		}
	}
	return best;
}

- (ProjectSidebarNode*)childOfNode:(ProjectSidebarNode*)node named:(NSString*)name
{
	ProjectSidebarNode* fallback = nil;
	for(ProjectSidebarNode* child in [self loadChildrenOfNode:node])
	{
		NSString* component = child.url.lastPathComponent;
		if([component isEqualToString:name])
			return child;
		if(!fallback && [component caseInsensitiveCompare:name] == NSOrderedSame)
			fallback = child;
	}
	return fallback;
}

- (void)scrollRowToCenterIfNeeded:(NSInteger)row
{
	if(row < 0 || row >= self.outlineView.numberOfRows)
		return;

	NSRect rowRect = [self.outlineView rectOfRow:row];
	if(NSContainsRect(self.outlineView.visibleRect, rowRect))
		return;

	NSScrollView* scrollView = self.outlineView.enclosingScrollView;
	NSClipView* clip = scrollView.contentView;
	CGFloat height = NSHeight(clip.bounds);
	CGFloat maxY = MAX(0, NSHeight(self.outlineView.frame) - height);
	CGFloat y = MIN(MAX(0, NSMidY(rowRect) - height / 2.0), maxY);
	[clip scrollToPoint:NSMakePoint(NSMinX(clip.bounds), y)];
	[scrollView reflectScrolledClipView:clip];
}

- (void)revealPath:(NSString*)path
{
	path = path.stringByStandardizingPath;
	if(path.length == 0)
		return;

	ProjectSidebarNode* root = [self rootContainingPath:path];
	if(!root)
		return;

	NSString* rootPath = root.url.path.stringByStandardizingPath;
	NSMutableArray<ProjectSidebarNode*>* chain = [NSMutableArray arrayWithObject:root];
	if(![path isEqualToString:rootPath])
	{
		NSString* relative = [path substringFromIndex:rootPath.length];
		ProjectSidebarNode* node = root;
		for(NSString* part in relative.pathComponents)
		{
			if(part.length == 0 || [part isEqualToString:@"/"])
				continue;
			ProjectSidebarNode* child = [self childOfNode:node named:part];
			if(!child)
				return;
			[chain addObject:child];
			node = child;
		}
	}

	self.suppressOpen = YES;
	for(ProjectSidebarNode* node in chain)
	{
		if(node.directory)
			[self.outlineView expandItem:node];
	}
	ProjectSidebarNode* target = chain.lastObject;
	NSInteger row = [self.outlineView rowForItem:target];
	if(row >= 0)
		[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	self.suppressOpen = NO;

	dispatch_async(dispatch_get_main_queue(), ^{
		[self scrollRowToCenterIfNeeded:[self.outlineView rowForItem:target]];
	});
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
	NSString* selected = self.pendingSelectPath ?: [self selectedPath];
	self.pendingSelectPath = nil;
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
	NSString* renamePath = self.pendingRenamePath;
	self.pendingRenamePath = nil;
	if(selected)
	{
		ProjectSidebarNode* node = [self nodeForPath:selected];
		NSInteger row = node ? [self.outlineView rowForItem:node] : -1;
		if(row >= 0)
			[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	}
	self.suppressOpen = NO;
	if(renamePath)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self beginRenameForPath:renamePath];
		});
	}
}

- (ProjectSidebarNode*)rootNodeForPath:(NSString*)path
{
	ProjectSidebarNode* node = [[ProjectSidebarNode alloc] init];
	node.url = [NSURL fileURLWithPath:path];
	node.name = path.lastPathComponent;
	BOOL isDirectory = NO;
	BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
	node.missing = !exists;
	node.directory = exists ? isDirectory : path.pathExtension.length == 0;
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

- (NSButton*)headerButtonWithSymbol:(NSString*)symbolName action:(SEL)action tooltip:(NSString*)tooltip
{
	NSImageSymbolConfiguration* symbol = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
	NSImage* image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip];
	image = [image imageWithSymbolConfiguration:symbol] ?: image;
	NSButton* button = [NSButton buttonWithImage:image target:self action:action];
	button.bezelStyle = NSBezelStyleInline;
	button.bordered = NO;
	button.toolTip = tooltip;
	button.translatesAutoresizingMaskIntoConstraints = NO;
	[button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	return button;
}

- (void)addSidebarFolderPaths:(NSArray<NSString*>*)newPaths
{
	NSMutableArray<NSString*>* paths = [ProjectSidebarFolderPaths() mutableCopy];
	NSMutableArray<NSString*>* added = [NSMutableArray array];
	for(NSString* raw in newPaths)
	{
		NSString* path = raw.stringByStandardizingPath;
		if(path.length == 0 || [paths containsObject:path])
			continue;
		[paths addObject:path];
		[added addObject:path];
	}
	if(added.count == 0)
		return;
	self.pendingExpand = added;
	ProjectSidebarSetFolderPaths(paths);
}

- (NSURL*)directoryForNewItems
{
	NSInteger row = self.outlineView.selectedRow;
	if(row >= 0 && row < self.outlineView.numberOfRows)
	{
		ProjectSidebarNode* node = [self.outlineView itemAtRow:row];
		NSURL* url = node.directory ? node.url : node.url.URLByDeletingLastPathComponent;
		BOOL isDirectory = NO;
		if(url.path.length && !node.missing && [NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory] && isDirectory)
			return [NSURL fileURLWithPath:url.path.stringByStandardizingPath isDirectory:YES];
	}
	return nil;
}

- (void)presentCreateFailureForURL:(NSURL*)url
{
	NSError* error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{
		NSLocalizedDescriptionKey: [NSString stringWithFormat:@"“%@” could not be created.", url.lastPathComponent],
	}];
	[self.view.window presentError:error];
}

- (void)beginCreatePanelWithName:(NSString*)name message:(NSString*)message completion:(void(^)(NSURL* url))completion
{
	NSSavePanel* panel = [NSSavePanel savePanel];
	panel.canCreateDirectories = YES;
	panel.showsTagField = NO;
	panel.nameFieldStringValue = name;
	panel.message = message;
	panel.prompt = @"Create";
	panel.delegate = self;
	NSWindow* window = self.view.window;
	void (^handler)(NSModalResponse) = ^(NSModalResponse result){
		panel.delegate = nil;
		if(result == NSModalResponseOK && panel.URL)
			completion(panel.URL);
	};
	if(window)
		[panel beginSheetModalForWindow:window completionHandler:handler];
	else
		handler([panel runModal]);
}

- (BOOL)panel:(id)sender validateURL:(NSURL*)url error:(NSError**)outError
{
	if([NSFileManager.defaultManager fileExistsAtPath:url.path])
	{
		if(outError)
		{
			*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{
				NSLocalizedDescriptionKey: @"An item with that name already exists.",
			}];
		}
		return NO;
	}
	return YES;
}

- (ProjectSidebarNode*)loadedNodeForPath:(NSString*)path
{
	path = path.stringByStandardizingPath;
	ProjectSidebarNode* root = [self rootContainingPath:path];
	if(!root)
		return nil;
	NSString* rootPath = root.url.path.stringByStandardizingPath;
	if([path isEqualToString:rootPath])
		return root;
	if(!root.children)
		return nil;

	ProjectSidebarNode* node = root;
	NSString* relative = [path substringFromIndex:rootPath.length];
	for(NSString* part in relative.pathComponents)
	{
		if(part.length == 0 || [part isEqualToString:@"/"])
			continue;
		if(!node.children)
			return nil;
		ProjectSidebarNode* child = nil;
		for(ProjectSidebarNode* candidate in node.children)
		{
			if([candidate.url.lastPathComponent isEqualToString:part])
			{
				child = candidate;
				break;
			}
		}
		if(!child)
			return nil;
		node = child;
	}
	return node;
}

- (void)refreshDirectoryContainingPath:(NSString*)path
{
	NSString* directory = path.stringByStandardizingPath.stringByDeletingLastPathComponent;
	ProjectSidebarNode* parent = [self loadedNodeForPath:directory];
	if(!parent)
		return;
	parent.children = nil;
	[self.outlineView reloadItem:parent reloadChildren:YES];
}

- (void)createItemInDirectory:(NSURL*)directory folder:(BOOL)folder
{
	NSURL* url = folder ? ProjectSidebarUniqueURL(directory, @"untitled folder", nil, YES) : ProjectSidebarUniqueURL(directory, @"untitled", @"txt", NO);
	if(!url)
		return;

	NSError* error = nil;
	BOOL created = folder ? [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&error] : [NSFileManager.defaultManager createFileAtPath:url.path contents:[NSData data] attributes:nil];
	if(!created)
	{
		if(error)
			[self.view.window presentError:error];
		else
			[self presentCreateFailureForURL:url];
		return;
	}

	NSString* path = url.path.stringByStandardizingPath;
	self.createdItemOpens = !folder;
	if(![self rootContainingPath:path])
	{
		self.pendingSelectPath = path;
		self.pendingRenamePath = path;
		[self addSidebarFolderPaths:@[ path ]];
		return;
	}

	[self refreshDirectoryContainingPath:path];
	[self revealPath:path];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self beginRenameForPath:path];
	});
}

- (void)beginRenameForPath:(NSString*)path
{
	path = path.stringByStandardizingPath;
	ProjectSidebarNode* node = [self nodeForPath:path];
	NSInteger row = node ? [self.outlineView rowForItem:node] : -1;
	if(row < 0)
	{
		if(self.createdItemOpens)
			[self.delegate projectSidebar:self openURL:[NSURL fileURLWithPath:path]];
		self.createdItemOpens = NO;
		self.preparedForRename = NO;
		return;
	}

	self.createdItemURL = node.url;
	self.preparedForRename = YES;
	[self.outlineView scrollRowToVisible:row];
	NSTableCellView* cell = [self.outlineView viewAtColumn:0 row:row makeIfNecessary:YES];
	cell.textField.editable = YES;
	cell.textField.selectable = YES;
	cell.textField.delegate = self;
	[self.outlineView editColumn:0 row:row withEvent:nil select:YES];
	if(!self.outlineView.currentEditor)
	{
		cell.textField.editable = NO;
		cell.textField.selectable = NO;
		self.preparedForRename = NO;
		NSURL* url = self.createdItemURL;
		BOOL open = self.createdItemOpens;
		self.createdItemURL = nil;
		self.createdItemOpens = NO;
		if(open)
			[self.delegate projectSidebar:self openURL:url];
		return;
	}

	if([self.outlineView.currentEditor isKindOfClass:NSTextView.class])
	{
		NSTextView* editor = (NSTextView*)self.outlineView.currentEditor;
		NSRange extension = [editor.string rangeOfString:@"." options:NSBackwardsSearch];
		if(extension.location != NSNotFound && extension.location > 0)
			[editor setSelectedRange:NSMakeRange(0, extension.location)];
	}
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldEditTableColumn:(NSTableColumn*)tableColumn item:(id)item
{
	ProjectSidebarNode* node = item;
	return self.preparedForRename && self.createdItemURL && [node.url.path.stringByStandardizingPath isEqualToString:self.createdItemURL.path.stringByStandardizingPath];
}

- (BOOL)control:(NSControl*)control textShouldEndEditing:(NSText*)fieldEditor
{
	if(self.createdItemURL)
		[self finishCreatedItemWithName:fieldEditor.string];
	return YES;
}

- (void)controlTextDidEndEditing:(NSNotification*)notification
{
	if(!self.createdItemURL)
		return;
	NSText* editor = notification.userInfo[@"NSFieldEditor"];
	NSString* name = [editor isKindOfClass:NSText.class] ? editor.string : self.createdItemURL.lastPathComponent;
	[self finishCreatedItemWithName:name];
}

- (BOOL)replaceSidebarPath:(NSString*)from withPath:(NSString*)to
{
	NSString* oldPath = from.stringByStandardizingPath;
	NSString* newPath = to.stringByStandardizingPath;
	NSMutableArray<NSString*>* paths = [ProjectSidebarFolderPaths() mutableCopy];
	NSUInteger index = [paths indexOfObject:oldPath];
	if(index == NSNotFound)
		return NO;
	paths[index] = newPath;
	self.pendingSelectPath = newPath;
	self.pendingExpand = @[ newPath ];
	ProjectSidebarSetFolderPaths(paths);
	return YES;
}

- (NSURL*)renameCreatedItemAtURL:(NSURL*)url toName:(NSString*)name
{
	name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if(name.length == 0 || [name isEqualToString:url.lastPathComponent] || [name containsString:@"/"] || [name isEqualToString:@"."] || [name isEqualToString:@".."])
		return url;

	BOOL isDirectory = NO;
	[NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory];
	NSURL* destination = [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:name isDirectory:isDirectory];
	if([NSFileManager.defaultManager fileExistsAtPath:destination.path])
	{
		NSError* error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{
			NSLocalizedDescriptionKey: @"An item with that name already exists.",
		}];
		[self.view.window presentError:error];
		return url;
	}

	NSError* error = nil;
	if(![NSFileManager.defaultManager moveItemAtURL:url toURL:destination error:&error])
	{
		[self.view.window presentError:error];
		return url;
	}
	[self replaceSidebarPath:url.path withPath:destination.path];
	return destination;
}

- (void)showFinishedItemAtURL:(NSURL*)url open:(BOOL)open refresh:(BOOL)refresh
{
	NSString* path = url.path.stringByStandardizingPath;
	if([ProjectSidebarFolderPaths() containsObject:path])
	{
		if(refresh)
			self.pendingSelectPath = path;
		else if(ProjectSidebarNode* node = [self nodeForPath:path])
			[self.outlineView reloadItem:node];
		if(open)
			[self.delegate projectSidebar:self openURL:url];
		return;
	}

	if(refresh)
		[self refreshDirectoryContainingPath:path];
	if(open)
		[self.delegate projectSidebar:self openURL:url];
	else if(refresh)
		[self revealPath:path];
	else if(ProjectSidebarNode* node = [self nodeForPath:path])
		[self.outlineView reloadItem:node];
}

- (void)finishCreatedItemWithName:(NSString*)name
{
	if(!self.createdItemURL)
		return;
	NSURL* url = self.createdItemURL;
	BOOL open = self.createdItemOpens;
	self.createdItemURL = nil;
	self.createdItemOpens = NO;
	self.preparedForRename = NO;
	dispatch_async(dispatch_get_main_queue(), ^{
		NSURL* finalURL = [self renameCreatedItemAtURL:url toName:name ?: @""];
		BOOL changed = ![finalURL.path.stringByStandardizingPath isEqualToString:url.path.stringByStandardizingPath];
		[self showFinishedItemAtURL:finalURL open:open refresh:changed];
	});
}

- (IBAction)newFolder:(id)sender
{
	NSURL* directory = [self directoryForNewItems];
	if(!directory)
	{
		[self beginCreatePanelWithName:@"untitled folder" message:@"Choose a name and location for the new folder. It will be added to the sidebar." completion:^(NSURL* url){
			NSError* error = nil;
			if(![NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&error])
			{
				[self.view.window presentError:error];
				return;
			}
			NSString* path = url.path.stringByStandardizingPath;
			if([self rootContainingPath:path])
			{
				[self refreshDirectoryContainingPath:path];
				[self revealPath:path];
			}
			else
			{
				[self addSidebarFolderPaths:@[ path ]];
			}
		}];
		return;
	}
	[self createItemInDirectory:directory folder:YES];
}

- (IBAction)newFile:(id)sender
{
	NSURL* directory = [self directoryForNewItems];
	if(!directory)
	{
		[self beginCreatePanelWithName:@"untitled.txt" message:@"Choose a name and location for the new file." completion:^(NSURL* url){
			if(![NSFileManager.defaultManager createFileAtPath:url.path contents:[NSData data] attributes:nil])
			{
				[self presentCreateFailureForURL:url];
				return;
			}
			[self showCreatedFileAtURL:url];
		}];
		return;
	}
	[self createItemInDirectory:directory folder:NO];
}

- (void)showCreatedFileAtURL:(NSURL*)url
{
	NSString* path = url.path.stringByStandardizingPath;
	if([self rootContainingPath:path])
	{
		[self refreshDirectoryContainingPath:path];
		[self revealPath:path];
	}
	else
	{
		self.pendingSelectPath = path;
		[self addSidebarFolderPaths:@[ path ]];
	}
	[self.delegate projectSidebar:self openURL:url];
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
		NSMutableArray<NSString*>* paths = [NSMutableArray array];
		for(NSURL* url in panel.URLs)
		{
			if(url.path.length)
				[paths addObject:url.path];
		}
		[self addSidebarFolderPaths:paths];
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

	cell.textField.stringValue = node.name ?: @"";
	BOOL fileRow = node.parent || !node.directory;
	cell.textField.font = fileRow ? [NSFont systemFontOfSize:NSFont.smallSystemFontSize] : [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
	cell.textField.textColor = node.missing ? NSColor.secondaryLabelColor : NSColor.labelColor;
	cell.textField.editable = NO;
	cell.textField.selectable = NO;
	cell.textField.delegate = self;
	cell.imageView.image = [NSWorkspace.sharedWorkspace iconForFile:node.url.path];
	cell.toolTip = node.parent ? nil : node.url.path;
	return cell;
}

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView*)outlineView pasteboardWriterForItem:(id)item
{
	ProjectSidebarNode* node = item;
	if(node.missing || (node.directory && node.parent))
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

- (NSArray<NSString*>*)pathsFromDraggingInfo:(id<NSDraggingInfo>)info
{
	NSMutableArray<NSString*>* moving = [NSMutableArray array];
	[info enumerateDraggingItemsWithOptions:0 forView:self.outlineView classes:@[ NSPasteboardItem.class ] searchOptions:@{} usingBlock:^(NSDraggingItem* draggingItem, NSInteger idx, BOOL* stop){
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
	return moving;
}

- (ProjectSidebarNode*)folderForDropOnNode:(ProjectSidebarNode*)node
{
	if(node.directory)
		return node;
	return node.parent.directory ? node.parent : nil;
}

- (BOOL)moveSidebarFilePaths:(NSArray<NSString*>*)paths intoFolder:(ProjectSidebarNode*)folder
{
	if(!folder.directory || folder.missing || paths.count == 0)
		return NO;

	NSString* destinationDir = folder.url.path.stringByStandardizingPath;
	NSMutableArray<NSString*>* roots = [ProjectSidebarFolderPaths() mutableCopy];
	NSString* movedPath = nil;
	for(NSString* raw in paths)
	{
		NSString* path = raw.stringByStandardizingPath;
		BOOL isDirectory = NO;
		if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory)
			continue;
		if([path.stringByDeletingLastPathComponent isEqualToString:destinationDir])
			continue;

		NSURL* destination = [NSURL fileURLWithPath:[destinationDir stringByAppendingPathComponent:path.lastPathComponent]];
		if([NSFileManager.defaultManager fileExistsAtPath:destination.path])
		{
			NSError* error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{
				NSLocalizedDescriptionKey: [NSString stringWithFormat:@"“%@” already exists in that folder.", destination.lastPathComponent],
			}];
			[self.view.window presentError:error];
			return NO;
		}

		NSError* error = nil;
		if(![NSFileManager.defaultManager moveItemAtURL:[NSURL fileURLWithPath:path] toURL:destination error:&error])
		{
			[self.view.window presentError:error];
			return NO;
		}
		if([self.delegate respondsToSelector:@selector(projectSidebar:didMoveURL:toURL:)])
			[self.delegate projectSidebar:self didMoveURL:[NSURL fileURLWithPath:path] toURL:destination];

		NSUInteger index = [roots indexOfObject:path];
		if(index != NSNotFound)
			[roots removeObjectAtIndex:index];
		movedPath = destination.path.stringByStandardizingPath;
		ProjectSidebarNode* source = [self loadedNodeForPath:path.stringByDeletingLastPathComponent];
		if(source && source != folder)
			source.children = nil;
	}
	if(!movedPath)
		return NO;

	self.pendingExpand = @[ destinationDir ];
	self.pendingSelectPath = movedPath;
	if(![roots isEqualToArray:ProjectSidebarFolderPaths()])
		ProjectSidebarSetFolderPaths(roots);
	else
	{
		folder.children = nil;
		[self.outlineView reloadData];
		[self.outlineView expandItem:folder];
		[self revealPath:movedPath];
	}
	return YES;
}

- (NSArray<NSURL*>*)externalFileURLsFromDraggingInfo:(id<NSDraggingInfo>)info
{
	if([[info.draggingPasteboard types] containsObject:ProjectSidebarDragType])
		return @[];

	NSMutableArray<NSURL*>* urls = [NSMutableArray array];
	NSArray<NSURL*>* found = [info.draggingPasteboard readObjectsForClasses:@[ NSURL.class ] options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
	for(NSURL* url in found)
	{
		if(url.isFileURL && url.path.length)
			[urls addObject:url];
	}
	return urls;
}

- (BOOL)path:(NSString*)path isInsideOrEqualTo:(NSString*)ancestor
{
	path = path.stringByStandardizingPath;
	ancestor = ancestor.stringByStandardizingPath;
	if(path.length == 0 || ancestor.length == 0)
		return NO;
	if([path isEqualToString:ancestor])
		return YES;
	NSString* prefix = [ancestor hasSuffix:@"/"] ? ancestor : [ancestor stringByAppendingString:@"/"];
	return [path hasPrefix:prefix];
}

- (BOOL)externalDropShouldCopy:(id<NSDraggingInfo>)info
{
	NSDragOperation mask = info.draggingSourceOperationMask;
	return (mask & NSDragOperationCopy) != 0 && (mask & NSDragOperationMove) == 0;
}

- (ProjectSidebarNode*)externalDropFolderForPoint:(NSPoint)point
{
	NSInteger row = [self.outlineView rowAtPoint:point];
	if(row < 0)
		return nil;
	return [self folderForDropOnNode:[self.outlineView itemAtRow:row]];
}

- (BOOL)addExternalFileURLs:(NSArray<NSURL*>*)urls atIndex:(NSInteger)index
{
	NSMutableArray<NSString*>* paths = [ProjectSidebarFolderPaths() mutableCopy];
	NSMutableArray<NSString*>* added = [NSMutableArray array];
	NSInteger insert = MAX(0, MIN(index, (NSInteger)paths.count));
	for(NSURL* url in urls)
	{
		NSString* path = url.path.stringByStandardizingPath;
		if(path.length == 0)
			continue;
		NSUInteger existing = [paths indexOfObject:path];
		if(existing != NSNotFound)
		{
			[paths removeObjectAtIndex:existing];
			if((NSInteger)existing < insert)
				--insert;
		}
		insert = MAX(0, MIN(insert, (NSInteger)paths.count));
		[paths insertObject:path atIndex:insert++];
		[added addObject:path];
	}
	if(added.count == 0)
		return NO;

	NSMutableArray<NSString*>* expand = [NSMutableArray array];
	for(NSString* path in added)
	{
		BOOL isDirectory = NO;
		if([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
			[expand addObject:path];
	}
	self.pendingExpand = expand;
	self.pendingSelectPath = added.lastObject;
	if(![paths isEqualToArray:ProjectSidebarFolderPaths()])
		ProjectSidebarSetFolderPaths(paths);

	for(NSString* path in added)
	{
		BOOL isDirectory = NO;
		if([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory)
			[self.delegate projectSidebar:self openURL:[NSURL fileURLWithPath:path]];
	}
	return YES;
}

- (BOOL)receiveExternalFileURLs:(NSArray<NSURL*>*)urls inFolder:(ProjectSidebarNode*)folder copy:(BOOL)copy
{
	if(!folder.directory || folder.missing || urls.count == 0)
		return NO;

	NSString* destinationDir = folder.url.path.stringByStandardizingPath;
	NSMutableArray<NSString*>* roots = [ProjectSidebarFolderPaths() mutableCopy];
	NSMutableArray<NSURL*>* filesToOpen = [NSMutableArray array];
	NSString* lastPath = nil;
	NSFileManager* fileManager = NSFileManager.defaultManager;
	for(NSURL* source in urls)
	{
		NSString* sourcePath = source.path.stringByStandardizingPath;
		BOOL isDirectory = NO;
		if(sourcePath.length == 0 || ![fileManager fileExistsAtPath:sourcePath isDirectory:&isDirectory])
			continue;
		if([destinationDir isEqualToString:sourcePath] || [self path:destinationDir isInsideOrEqualTo:sourcePath])
			continue;
		if([sourcePath.stringByDeletingLastPathComponent isEqualToString:destinationDir])
		{
			lastPath = sourcePath;
			if(!isDirectory)
				[filesToOpen addObject:[NSURL fileURLWithPath:sourcePath]];
			continue;
		}

		NSURL* destination = [NSURL fileURLWithPath:[destinationDir stringByAppendingPathComponent:sourcePath.lastPathComponent]];
		if([fileManager fileExistsAtPath:destination.path])
		{
			NSError* error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{
				NSLocalizedDescriptionKey: [NSString stringWithFormat:@"“%@” already exists in that folder.", destination.lastPathComponent],
			}];
			[self.view.window presentError:error];
			continue;
		}

		BOOL copyItem = copy;
		if(!copyItem)
		{
			id sourceVolume = nil;
			id destinationVolume = nil;
			[source getResourceValue:&sourceVolume forKey:NSURLVolumeIdentifierKey error:nil];
			[[NSURL fileURLWithPath:destinationDir isDirectory:YES] getResourceValue:&destinationVolume forKey:NSURLVolumeIdentifierKey error:nil];
			if(sourceVolume && destinationVolume && ![sourceVolume isEqual:destinationVolume])
				copyItem = YES;
		}

		NSError* error = nil;
		BOOL ok = copyItem ? [fileManager copyItemAtURL:source toURL:destination error:&error] : [fileManager moveItemAtURL:source toURL:destination error:&error];
		if(!ok)
		{
			if(error)
				[self.view.window presentError:error];
			continue;
		}

		NSString* placed = destination.path.stringByStandardizingPath;
		if(!copyItem)
		{
			if([self.delegate respondsToSelector:@selector(projectSidebar:didMoveURL:toURL:)])
				[self.delegate projectSidebar:self didMoveURL:[NSURL fileURLWithPath:sourcePath] toURL:destination];
			NSUInteger index = [roots indexOfObject:sourcePath];
			if(index != NSNotFound)
				[roots removeObjectAtIndex:index];
		}
		lastPath = placed;
		if(!isDirectory)
			[filesToOpen addObject:[NSURL fileURLWithPath:placed]];
	}
	if(!lastPath)
		return NO;

	self.pendingExpand = @[ destinationDir ];
	self.pendingSelectPath = lastPath;
	if(![roots isEqualToArray:ProjectSidebarFolderPaths()])
		ProjectSidebarSetFolderPaths(roots);
	else
	{
		folder.children = nil;
		[self.outlineView reloadItem:folder reloadChildren:YES];
		[self.outlineView expandItem:folder];
		[self revealPath:lastPath];
	}
	for(NSURL* url in filesToOpen)
		[self.delegate projectSidebar:self openURL:url];
	return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView*)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
	NSArray<NSURL*>* external = [self externalFileURLsFromDraggingInfo:info];
	if(external.count)
	{
		NSPoint point = [outlineView convertPoint:info.draggingLocation fromView:nil];
		ProjectSidebarNode* folder = [self externalDropFolderForPoint:point];
		if(folder)
		{
			for(NSURL* url in external)
			{
				if([self path:folder.url.path isInsideOrEqualTo:url.path])
					return NSDragOperationNone;
			}
			if(item != folder || index != NSOutlineViewDropOnItemIndex)
				[outlineView setDropItem:folder dropChildIndex:NSOutlineViewDropOnItemIndex];
			return [self externalDropShouldCopy:info] ? NSDragOperationCopy : NSDragOperationMove;
		}

		NSInteger insertion = [self rootInsertionIndexForPoint:point];
		if(item != nil || index != insertion)
			[outlineView setDropItem:nil dropChildIndex:insertion];
		return NSDragOperationCopy;
	}

	if(![[info.draggingPasteboard types] containsObject:ProjectSidebarDragType])
		return NSDragOperationNone;

	NSString* draggedPath = [info.draggingPasteboard stringForType:ProjectSidebarDragType].stringByStandardizingPath;
	BOOL draggedIsDirectory = NO;
	BOOL draggedExists = draggedPath.length && [NSFileManager.defaultManager fileExistsAtPath:draggedPath isDirectory:&draggedIsDirectory];
	NSPoint point = [outlineView convertPoint:info.draggingLocation fromView:nil];
	if(draggedExists && !draggedIsDirectory)
	{
		NSInteger row = [outlineView rowAtPoint:point];
		ProjectSidebarNode* node = row >= 0 ? [outlineView itemAtRow:row] : nil;
		ProjectSidebarNode* folder = [self folderForDropOnNode:node];
		NSString* destinationDir = folder.url.path.stringByStandardizingPath;
		if(folder && destinationDir.length && ![draggedPath.stringByDeletingLastPathComponent isEqualToString:destinationDir])
		{
			if(item != folder || index != NSOutlineViewDropOnItemIndex)
				[outlineView setDropItem:folder dropChildIndex:NSOutlineViewDropOnItemIndex];
			return NSDragOperationMove;
		}
	}

	if(![ProjectSidebarFolderPaths() containsObject:draggedPath])
		return NSDragOperationNone;

	NSInteger insertion = [self rootInsertionIndexForPoint:point];
	if(item != nil || index != insertion)
		[outlineView setDropItem:nil dropChildIndex:insertion];
	return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
	NSArray<NSURL*>* external = [self externalFileURLsFromDraggingInfo:info];
	if(external.count)
	{
		if([item isKindOfClass:ProjectSidebarNode.class] && ((ProjectSidebarNode*)item).directory && index == NSOutlineViewDropOnItemIndex)
			return [self receiveExternalFileURLs:external inFolder:item copy:[self externalDropShouldCopy:info]];
		return [self addExternalFileURLs:external atIndex:index];
	}

	NSArray<NSString*>* moving = [self pathsFromDraggingInfo:info];
	if(moving.count == 0)
		return NO;
	if([item isKindOfClass:ProjectSidebarNode.class] && ((ProjectSidebarNode*)item).directory && index == NSOutlineViewDropOnItemIndex)
		return [self moveSidebarFilePaths:moving intoFolder:item];
	if(item != nil)
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
