/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: UserManager.h
 *	Module		: ユーザ一覧管理クラス
 *============================================================================*/

#import <Foundation/Foundation.h>

@class UserInfo;

/*============================================================================*
 * Notification 通知キー
 *============================================================================*/

// ユーザ一覧変更
#define NOTICE_USER_LIST_CHANGED		@"IPMsgUserListChanged"

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface UserManager : NSObject {
	NSMutableArray*		userList;		// ユーザ一覧
	NSMutableSet*		dialupSet;		// ダイアルアップアドレス一覧
	NSRecursiveLock*	lock;			// 更新排他用ロック
}

// ファクトリ
+ (UserManager*)sharedManager;

// ユーザ情報取得
- (NSArray*)users;
- (int)numberOfUsers;
- (UserInfo*)userForLogOnUser:(NSString*)logOn address:(UInt32)addr port:(UInt16)port;

// ユーザ情報追加／削除
- (void)appendUser:(UserInfo*)info;
- (void)setVersion:(NSString*)version ofUser:(UserInfo*)user;
- (void)removeUser:(UserInfo*)info;
- (void)removeAllUsers;

// その他
- (NSArray*)dialupAddresses;

@end
