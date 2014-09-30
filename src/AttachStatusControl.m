/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AttachStatusControl.m
 *	Module		: 添付ファイル状況表示パネルコントローラ
 *============================================================================*/

#import "AttachStatusControl.h"
#import "UserInfo.h"
#import "Attachment.h"
#import "AttachmentFile.h"
#import "AttachmentServer.h"
#import "MessageCenter.h"
#import "DebugLog.h"

static NSString* ATTACHPNL_SIZE_W	= @"AttachStatusPanelWidth";
static NSString* ATTACHPNL_SIZE_H	= @"AttachStatusPanelHeight";
static NSString* ATTACHPNL_POS_X	= @"AttachStatusPanelOriginX";
static NSString* ATTACHPNL_POS_Y	= @"AttachStatusPanelOriginY";

@implementation AttachStatusControl

- (id)init {
	self = [super init];
	if (self) {
		// データのロード
		[attachTable reloadData];

		// 添付リスト変更の通知登録
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(attachListChanged:)
													 name:NOTICE_ATTACH_LIST_CHANGED
												   object:nil];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (IBAction)buttonPressed:(id)sender {
	if (sender == deleteButton) {
		id item = [attachTable itemAtRow:[attachTable selectedRow]];
		if ([item isKindOfClass:[NSNumber class]]) {
			if ([AttachmentServer isAvailable]) {
				[[AttachmentServer sharedServer] removeAttachmentByMessageID:item];
				[attachTable deselectAll:self];
			}
		} else if ([item isKindOfClass:[Attachment class]]) {
			if ([AttachmentServer isAvailable]) {
				int	i;
				for (i = [attachTable selectedRow]; i >= 0; i--) {
					id val = [attachTable itemAtRow:i];
					if ([val isKindOfClass:[NSNumber class]]) {
						[[AttachmentServer sharedServer] removeAttachmentByMessageID:val fileID:[item fileID]];
						[attachTable deselectAll:self];
						break;
					}
				}
			}
		} else if ([item isKindOfClass:[UserInfo class]]) {
			if ([AttachmentServer isAvailable]) {
				int			i;
				NSNumber*	fid = nil;
				for (i = [attachTable selectedRow]; i >= 0; i--) {
					id val = [attachTable itemAtRow:i];
					if ([val isKindOfClass:[Attachment class]]) {
						if (fid == nil) {
							fid = [val fileID];
						}
					} else if ([val isKindOfClass:[NSNumber class]]) {
						if (fid) {
							[[AttachmentServer sharedServer] removeUser:item messageID:val fileID:fid];
							[attachTable deselectAll:self];
						} else {
							ERR(@"Internal Error(fid is nil)");
						}
						break;
					}
				}
			}
		}
	} else {
		ERR(@"Unknown Button Pressed(%@)", sender);
	}
}

- (IBAction)checkboxChanged:(id)sender {
	if (sender == dispAlwaysCheck) {
		[panel setHidesOnDeactivate:([dispAlwaysCheck state] == NSOffState)];
	} else {
		ERR(@"Unknown Checkbox Changed(%@)", sender);
	}
}

- (void)attachListChanged:(NSNotification*)aNotification {
	[attachTable reloadData];
}

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	if (!item) {
		if ([AttachmentServer isAvailable]) {
			return [[AttachmentServer sharedServer] numberOfMessageIDs];
		}
	} else if ([item isKindOfClass:[NSNumber class]]) {
		if ([AttachmentServer isAvailable]) {
			return [[AttachmentServer sharedServer] numberOfAttachmentsInMessageID:item];
		}
	} else if ([item isKindOfClass:[Attachment class]]) {
		return [item numberOfUsers];
	} else {
		WRN(@"not yet(number of children of %@)", item);
	}
	return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item {
	if (!item) {
		if ([AttachmentServer isAvailable]) {
			return [[AttachmentServer sharedServer] messageIDAtIndex:index];
		}
	} else if ([item isKindOfClass:[NSNumber class]]) {
		if ([AttachmentServer isAvailable]) {
			return [[AttachmentServer sharedServer] attachmentInMessageID:item atIndex:index];
		}
	} else if ([item isKindOfClass:[Attachment class]]) {
		return [item userAtIndex:index];
	} else {
		WRN(@"not yet(#%d child of %@)", index, item);
	}
	return nil;
}

- (id)outlineView:(NSOutlineView*)outlineView objectValueForTableColumn:(NSTableColumn*)tableColumn byItem:(id)item {
	if ([item isKindOfClass:[NSNumber class]]) {
		return [NSString stringWithFormat:@"Message[ID:%@]", item];
	} else if ([item isKindOfClass:[Attachment class]]) {
		Attachment*	sendAttach = item;
		return [NSString stringWithFormat:@"%@ (Remain Users:%d)",
						[[sendAttach file] name], [sendAttach numberOfUsers]];
	} else if ([item isKindOfClass:[UserInfo class]]) {
		UserInfo* user = item;
		return user.summaryString;
	}
	return item;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	if (!item) {
		return ([[AttachmentServer sharedServer] numberOfMessageIDs] > 0);
	} else if ([item isKindOfClass:[NSNumber class]]) {
		return YES;
	} else if ([item isKindOfClass:[Attachment class]]) {
		return YES;
	} else if ([item isKindOfClass:[UserInfo class]]) {
		return NO;
	} else {
		WRN(@"not yet(isExpandable %@)", item);
	}
	return NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	[deleteButton setEnabled:([attachTable selectedRow] != -1)];
}

- (void)windowDidMove:(NSNotification *)aNotification {
	if ([panel isVisible]) {
		NSUserDefaults*	defaults	= [NSUserDefaults standardUserDefaults];
		NSPoint			origin		= [panel frame].origin;
		[defaults setObject:[NSNumber numberWithFloat:origin.x] forKey:ATTACHPNL_POS_X];
		[defaults setObject:[NSNumber numberWithFloat:origin.y] forKey:ATTACHPNL_POS_Y];
	}
}

- (void)windowDidResize:(NSNotification *)aNotification {
	if ([panel isVisible]) {
		NSUserDefaults*	defaults	= [NSUserDefaults standardUserDefaults];
		NSSize			size		= [panel frame].size;
		[defaults setObject:[NSNumber numberWithFloat:size.width] forKey:ATTACHPNL_SIZE_W];
		[defaults setObject:[NSNumber numberWithFloat:size.height] forKey:ATTACHPNL_SIZE_H];
	}
}

// 初期化
- (void)awakeFromNib {
	NSUserDefaults*	defaults	= [NSUserDefaults standardUserDefaults];
	NSNumber*		originX		= [defaults objectForKey:ATTACHPNL_POS_X];
	NSNumber*		originY		= [defaults objectForKey:ATTACHPNL_POS_Y];
	NSNumber*		sizeWidth	= [defaults objectForKey:ATTACHPNL_SIZE_W];
	NSNumber*		sizeHeight	= [defaults objectForKey:ATTACHPNL_SIZE_H];
	NSRect			windowFrame;
	if ((originX != nil) && (originY != nil) && (sizeWidth != nil) && (sizeHeight != nil)) {
		windowFrame.origin.x	= [originX floatValue];
		windowFrame.origin.y	= [originY floatValue];
		windowFrame.size.width	= [sizeWidth floatValue];
		windowFrame.size.height	= [sizeHeight floatValue];
	} else {
		NSRect screenFrame		= [[NSScreen mainScreen] frame];
		windowFrame				= [panel frame];
		windowFrame.origin.x	= screenFrame.size.width - windowFrame.size.width - 5;
		windowFrame.origin.y	= screenFrame.size.height - windowFrame.size.height
									- [[NSStatusBar systemStatusBar] thickness] - 5;
	}
	[panel setFrame:windowFrame display:NO];
	[panel setFloatingPanel:NO];
}

@end
