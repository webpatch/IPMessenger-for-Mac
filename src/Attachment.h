/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: Attachment.h
 *	Module		: 添付ファイル情報クラス
 *============================================================================*/

#include <Cocoa/Cocoa.h>

@class AttachmentFile;
@class UserInfo;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface Attachment : NSObject <NSCopying>
{
	NSNumber*		_fileID;
	AttachmentFile*	_file;
	NSImage*		_icon;
	BOOL			_download;
	NSMutableArray*	_sentUsers;		// 送信ユーザ（送信ファイル用）
}

@property(retain,readwrite)	NSNumber*		fileID;			// ファイルID
@property(retain,readonly)	AttachmentFile*	file;			// ファイルオブジェクト
@property(retain,readonly)	NSImage*		icon;			// ファイルアイコン
@property(assign,readwrite)	BOOL			isDownloaded;	// DL済みフラグ（受信用）

// ファクトリ
+ (id)attachmentWithFile:(AttachmentFile*)attach;
+ (id)attachmentWithMessage:(NSString*)str;

// 初期化
- (id)initWithFile:(AttachmentFile*)attach;
- (id)initWithMessage:(NSString*)str;

// 送信ユーザ管理
- (void)addUser:(UserInfo*)user;
- (void)removeUser:(UserInfo*)user;
- (NSUInteger)numberOfUsers;
- (UserInfo*)userAtIndex:(NSUInteger)index;
- (BOOL)containsUser:(UserInfo*)user;

@end
