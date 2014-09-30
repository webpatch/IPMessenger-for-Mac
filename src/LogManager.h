/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: LogManager.h
 *	Module		: ログ管理クラス
 *============================================================================*/

#import <Foundation/Foundation.h>

@class RecvMessage;
@class SendMessage;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface LogManager : NSObject
{
	NSFileManager*		_fileManager;
	NSString*			_filePath;
	NSString*			_sTypeBroadcast;
	NSString*			_sTypeMulticast;
	NSString*			_sTypeAutoReturn;
	NSString*			_sTypeLocked;
	NSString*			_sTypeSealed;
	NSString*			_sTypeAttached;
	NSDateFormatter*	_dateFormat;
}

@property(copy,readwrite)	NSString*	filePath;		// ログファイルパス

// ファクトリ
+ (LogManager*)standardLog;
+ (LogManager*)alternateLog;

// ログ出力
- (void)writeRecvLog:(RecvMessage*)info;
- (void)writeRecvLog:(RecvMessage*)info withRange:(NSRange)range;
- (void)writeSendLog:(SendMessage*)info to:(NSArray*)to;

@end
