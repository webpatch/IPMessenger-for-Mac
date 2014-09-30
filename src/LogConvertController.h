/*============================================================================*
 * (C) 2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: LogConvertController.h
 *	Module		: ログ変換ダイアログコントローラクラス
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import "LogConverter.h"

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface LogConvertController : NSWindowController <LogConvertDelegate>
{
	IBOutlet NSProgressIndicator*	_progressBar;
	IBOutlet NSProgressIndicator*	_indicator;
	NSString*						_filePath;
	NSUInteger						_totalStep;
	NSDate*							_start;
	NSString*						_lines;
	NSString*						_remain;
}

@property(copy,readwrite)	NSString*	filePath;
@property(retain,readonly)	NSString*	lines;
@property(retain,readonly)	NSString*	remainTime;

@end
