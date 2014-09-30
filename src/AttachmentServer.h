/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AttachmentServer.h
 *	Module		: 送信添付ファイル管理クラス
 *============================================================================*/

#import <Foundation/Foundation.h>

@class UserInfo;
@class Attachment;

/*============================================================================*
 * Notification 通知キー
 *============================================================================*/

// ユーザ一覧変更
#define NOTICE_ATTACH_LIST_CHANGED		@"IPMsgAttachmentListChanged"

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface AttachmentServer : NSObject {
	int						serverSock;		// ソケットディスクリプタ（サーバ待受用）
	NSLock*					serverLock;		// サーバスレッド終了同期用ロック
	BOOL					shutdown;		// 終了フラグ
	NSMutableDictionary*	attachDic;		// 添付ファイル辞書
	NSLock*					lockObj;		// 排他制御用ロック
	NSFileManager*			fileManager;	// ファイルマネージャ
}

// ファクトリ
+ (AttachmentServer*)sharedServer;
+ (BOOL)isAvailable;

// 送信添付ファイル追加
- (void)addAttachment:(Attachment*)attach messageID:(NSNumber*)mid;
// 添付ファイル管理情報破棄
- (void)removeAttachmentByMessageID:(NSNumber*)mid;
- (void)removeAttachmentByMessageID:(NSNumber*)mid fileID:(NSNumber*)fid;
- (void)removeAttachmentsByMessageID:(NSNumber*)mid needLock:(BOOL)lockFlag clearTimer:(BOOL)clearFlag;

// 添付ファイル送信ユーザ追加
- (void)addUser:(UserInfo*)user messageID:(NSNumber*)mid;
// 添付ファイル送信ユーザ確認
- (BOOL)containsUser:(UserInfo*)user messageID:(NSNumber*)mid fileID:(NSNumber*)fid;

// 添付ファイル送信ユーザ削除
- (void)removeUser:(UserInfo*)user;
- (void)removeUser:(UserInfo*)user messageID:(NSNumber*)mid;
- (void)removeUser:(UserInfo*)user messageID:(NSNumber*)mid fileID:(NSNumber*)fid;

// 添付ファイル情報取得
- (Attachment*)attachmentWithMessageID:(NSNumber*)mid fileID:(NSNumber*)fid;

- (void)shutdownServer;

// 暫定
- (int)numberOfMessageIDs;
- (NSNumber*)messageIDAtIndex:(int)index;
- (int)numberOfAttachmentsInMessageID:(NSNumber*)mid;
- (Attachment*)attachmentInMessageID:(NSNumber*)mid atIndex:(int)index;

@end
