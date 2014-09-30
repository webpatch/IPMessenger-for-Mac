/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: SendMessage.h
 *	Module		: 送信メッセージクラス
 *============================================================================*/

#import <Foundation/Foundation.h>

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface SendMessage : NSObject <NSCopying>
{
	NSInteger	_packetNo;
	NSString*	_message;
	NSArray*	_attach;
	BOOL		_sealed;
	BOOL		_locked;
}

@property(readonly)			NSInteger	packetNo;		// パケット番号
@property(copy,readonly)	NSString*	message;		// 送信メッセージ
@property(retain,readonly)	NSArray*	attachments;	// 添付ファイル
@property(readonly)			BOOL		sealed;			// 封書フラグ
@property(readonly)			BOOL		locked;			// 施錠フラグ

// ファクトリ
+ (id)messageWithMessage:(NSString*)msg
			 attachments:(NSArray*)attach
					seal:(BOOL)seal
					lock:(BOOL)lock;

// 初期化
- (id)initWithMessage:(NSString*)msg
		  attachments:(NSArray*)attach
				 seal:(BOOL)seal
				 lock:(BOOL)lock;

@end
