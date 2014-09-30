/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: RetryInfo.m
 *	Module		: メッセージ再送情報クラス
 *============================================================================*/

#import "RetryInfo.h"
#import "UserInfo.h"

@interface RetryInfo()
@property(assign,readwrite)	UInt32		command;
@property(assign,readwrite)	UserInfo*	toUser;
@property(assign,readwrite)	NSString*	message;
@property(assign,readwrite)	NSString*	option;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation RetryInfo

@synthesize	command		= _command;
@synthesize toUser		= _toUser;
@synthesize message		= _message;
@synthesize option		= _option;
@synthesize retryCount	= _retry;

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

+ (RetryInfo*)infoWithCommand:(UInt32)cmd
						   to:(UserInfo*)to
					  message:(NSString*)msg
					   option:(NSString*)opt
{
	return [[[RetryInfo alloc] initWithCommand:cmd to:to message:msg option:opt] autorelease];
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)initWithCommand:(UInt32)cmd
				   to:(UserInfo*)to
			  message:(NSString*)msg
			   option:(NSString*)opt
{
	self = [super init];
	if (self) {
		self.command	= cmd;
		self.toUser		= [to retain];
		self.message	= [msg retain];
		self.option		= [opt retain];
		self.retryCount	= 0;
	}
	return self;
}

// 解放
- (void)dealloc
{
	[_toUser release];
	[_message release];
	[_option release];
	[super dealloc];
}

@end
