/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: NoticeControl.h
 *	Module		: 通知ダイアログコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface NoticeControl : NSObject
{
	IBOutlet NSWindow*		window;			// ダイアログ
	IBOutlet NSTextField*	titleLabel;		// タイトルラベル
	IBOutlet NSTextField*	messageLabel;	// メッセージラベル
	IBOutlet NSTextField*	dateLabel;		// 日付ラベル
}

// 初期化
- (id)initWithTitle:(NSString*)title
			message:(NSString*)msg
			   date:(NSDate*)date;

@end
