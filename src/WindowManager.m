/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: WindowManager.m
 *	Module		: 送受信ウィンドウ管理クラス
 *============================================================================*/

#import "WindowManager.h"
#import "ReceiveControl.h"
#import "SendControl.h"
#import "DebugLog.h"

#define	_DEBUG_DETAIL	0

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation WindowManager

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

+ (WindowManager*)sharedManager {
	static WindowManager* shared = nil;
	if (!shared) {
		shared = [[WindowManager alloc] init];
	}
	return shared;
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)init {
	self = [super init];
	receiveDic	= [[NSMutableDictionary alloc] init];
	replyDic	= [[NSMutableDictionary alloc] init];
	return self;
}

// 解放
- (void)dealloc {
	[receiveDic	release];
	[replyDic	release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * 内部利用
 *----------------------------------------------------------------------------*/

#if _DEBUG_DETAIL
- (void)report:(NSString*)msg {
	int			i;
	int			num;
	NSArray*	keys;

	DBG(msg);
	num		= [receiveDic count];
	keys	= [receiveDic allKeys];
	DBG(@"  ReceiveWin:num=%d", num);
	for (i = 0; i < num; i++) {
		id key = [keys objectAtIndex:i];
		id obj = [receiveDic objectForKey:key];
		DBG3(@"  ReceiveWin[%d]:id=%@,obj=%@", i, key, obj);
	}
	num		= [replyDic count];
	keys	= [replyDic allKeys];
	DBG(@"  ReplyWin:num=%d", num);
	for (i = 0; i < num; i++) {
		id key = [keys objectAtIndex:i];
		id obj = [replyDic objectForKey:key];
		DBG3(@"  ReplyWin  [%d]:id=%@,obj=%@", i, key, obj);
	}
}
#endif

/*----------------------------------------------------------------------------*
 * 受信ウィンドウ管理
 *----------------------------------------------------------------------------*/

// 管理する受信ウィンドウ数を返す
- (int)numberOfReceiveWindows {
	return [receiveDic count];
}

// キーに対応する受信ウィンドウを返す
- (ReceiveControl*)receiveWindowForKey:(id)aKey {
	return (ReceiveControl*)[receiveDic objectForKey:aKey];
}

// 受信ウィンドウを登録する
- (void)setReceiveWindow:(ReceiveControl*)aWindow forKey:(id)aKey {
	if (aKey && aWindow) {
		[receiveDic setObject:aWindow forKey:aKey];
	}
#if _DEBUG_DETAIL
	[self report:[NSString stringWithFormat:@"WinMng:ReceiveWindow set(%@)", aKey]];
#endif
}

// 受信ウィンドウを削除する
- (void)removeReceiveWindowForKey:(id)aKey {
	if (aKey) {
		[receiveDic removeObjectForKey:aKey];
	}
#if _DEBUG_DETAIL
	[self report:[NSString stringWithFormat:@"WinMng:ReceiveWindow remove(%@)", aKey]];
#endif
}

/*----------------------------------------------------------------------------*
 * 返信ウィンドウ管理
 *----------------------------------------------------------------------------*/

// 管理する返信ウィンドウ数を返す
- (int)numberOfReplyWindows {
	return [replyDic count];
}

// 返信ウィンドウを返す
- (SendControl*)replyWindowForKey:(id)aKey {
	return (SendControl*)[replyDic objectForKey:aKey];
}

// 返信ウィンドウを登録する
- (void)setReplyWindow:(SendControl*)aWindow forKey:(id)aKey {
	if (aKey && aWindow) {
		[replyDic setObject:aWindow forKey:aKey];
	}
#if _DEBUG_DETAIL
	[self report:[NSString stringWithFormat:@"WinMng:ReplyWindow set(%@)", aKey]];
#endif
}

// 返信ウィンドウを削除する
- (void)removeReplyWindowForKey:(id)aKey {
	if (aKey) {
		[replyDic removeObjectForKey:aKey];
	}
#if _DEBUG_DETAIL
	[self report:[NSString stringWithFormat:@"WinMng:ReplyWindow remove(%@)", aKey]];
#endif
}

@end
