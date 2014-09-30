/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: Attachment.m
 *	Module		: 添付ファイル情報クラス
 *============================================================================*/

#import "Attachment.h"
#import "IPMessenger.h"
#import "AttachmentFile.h"
#import "UserInfo.h"
#import "DebugLog.h"

@interface Attachment()
@property(retain,readwrite)	AttachmentFile*	file;
@property(retain,readwrite)	NSImage*		icon;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation Attachment

@synthesize fileID			= _fileID;
@synthesize file			= _file;
@synthesize icon			= _icon;
@synthesize	isDownloaded	= _download;

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

+ (id)attachmentWithFile:(AttachmentFile*)attach
{
	return [[[Attachment alloc] initWithFile:attach] autorelease];
}

+ (id)attachmentWithMessage:(NSString*)str
{
	return [[[Attachment alloc] initWithMessage:str] autorelease];
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化（送信用）
- (id)initWithFile:(AttachmentFile*)attach
{
	self = [super init];
	if (self) {
		self.file	= attach;
		self.icon	= [self.file iconImage];
		[self.icon setSize:NSMakeSize(16, 16)];
		_sentUsers	= [[NSMutableArray alloc] init];
	}
	return self;
}

// 初期化（受信用）
- (id)initWithMessage:(NSString*)str
{
	if (self = [super init]) {
		NSArray*	strs	= [str componentsSeparatedByString:@":"];
		NSRange		range	= {1, [strs count] - 1};
		NSString*	info	= [[strs subarrayWithRange:range] componentsJoinedByString:@":"];

		self.fileID	= [NSNumber numberWithInteger:[[strs objectAtIndex:0] integerValue]];
		self.file	= [AttachmentFile fileWithMessage:info];
		self.icon	= [self.file iconImage];
		[self.icon setSize:NSMakeSize(16, 16)];
		_sentUsers	= [[NSMutableArray alloc] init];
	}

	return self;
}

// 解放
- (void)dealloc
{
	[_fileID release];
	[_file release];
	[_icon release];
	[_sentUsers release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * 送信ユーザ管理
 *----------------------------------------------------------------------------*/

// 送信ユーザ追加
- (void)addUser:(UserInfo*)user
{
	if (![self containsUser:user]) {
		[_sentUsers addObject:user];
	}
}

// 送信ユーザ削除
- (void)removeUser:(UserInfo*)user
{
	[_sentUsers removeObject:user];
}

// 送信ユーザ数
- (NSUInteger)numberOfUsers
{
	return [_sentUsers count];
}

// インデックス指定ユーザ情報
- (UserInfo*)userAtIndex:(NSUInteger)index
{
	return [_sentUsers objectAtIndex:index];
}

// 送信ユーザ検索
- (BOOL)containsUser:(UserInfo*)user {
	return [_sentUsers containsObject:user];
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

// オブジェクト概要
- (NSString*)description
{
	return [NSString stringWithFormat:@"AttachmentItem[FileID:%@,File:%@,Users:%d]",
							self.fileID, [self.file name], [_sentUsers count]];
}

// オブジェクトコピー処理
- (id)copyWithZone:(NSZone*)zone
{
	Attachment* newObj = [[self class] allocWithZone:zone];
	if (newObj) {
		newObj->_fileID		= [self->_fileID retain];
		newObj->_file		= [self->_file retain];
		newObj->_icon		= [self->_icon retain];
		newObj->_download	= self->_download;
		newObj->_sentUsers	= [self->_sentUsers retain];
	}
	return newObj;
}

@end
