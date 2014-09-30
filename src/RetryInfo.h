/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: RetryInfo.h
 *	Module		: メッセージ再送情報クラス
 *============================================================================*/

#import <Foundation/Foundation.h>

@class UserInfo;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface RetryInfo : NSObject
{
	UInt32		_command;
	UserInfo*	_toUser;
	NSString*	_message;
	NSString*	_option;
	NSInteger	_retry;
}

@property(readonly)		UInt32		command;		// 送信コマンド
@property(readonly)		UserInfo*	toUser;			// 送信相手
@property(readonly)		NSString*	message;		// メッセージ文字列
@property(readonly)		NSString*	option;			// 拡張メッセージ文字列
@property(readwrite)	NSInteger	retryCount;		// リトライ階数

// ファクトリ
+ (RetryInfo*)infoWithCommand:(UInt32)cmd to:(UserInfo*)to message:(NSString*)msg option:(NSString*)opt;

// 初期化
- (id)initWithCommand:(UInt32)cmd to:(UserInfo*)to message:(NSString*)msg option:(NSString*)opt;

@end
