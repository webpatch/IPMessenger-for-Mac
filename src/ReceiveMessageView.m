/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: ReceiveMessageView.m
 *	Module		: 受信メッセージ表示View
 *============================================================================*/

#import "ReceiveMessageView.h"
#import "Config.h"

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation ReceiveMessageView

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		[self setEditable:NO];
		[self setBackgroundColor:[NSColor windowBackgroundColor]];
		[self setFont:[Config sharedConfig].receiveMessageFont];
		[self setUsesRuler:YES];
	}
	return self;
}

- (void)changeFont:(id)sender
{
	[self setFont:[sender convertFont:[self font]]];
}

@end
