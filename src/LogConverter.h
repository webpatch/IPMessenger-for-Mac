/*============================================================================*
 * (C) 2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: LogConverter.h
 *	Module		: ログファイル変換（SJIS→UTF-8）
 *============================================================================*/

#import <Cocoa/Cocoa.h>

@class LogConverter;

/*============================================================================*
 * プロトコル定義
 *============================================================================*/

// Delegate
@protocol LogConvertDelegate <NSObject>
- (void)logConverter:(LogConverter*)aConverter prepare:(NSString*)aFilePath;
- (void)logConverter:(LogConverter*)aConverter start:(NSUInteger)aTotalStep;
- (void)logConverter:(LogConverter*)aConverter progress:(NSUInteger)aStep;
- (void)logConverter:(LogConverter*)aConverter finish:(BOOL)aResult;
@end

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface LogConverter : NSObject
{
	NSString*		_name;
	NSString*		_path;
	NSString*		_backupPath;
	NSFileManager*	_fileManager;
	NSData*			_bom;
	id				_delegate;
}

@property(copy,readwrite)	NSString*				name;
@property(copy,readwrite)	NSString*				path;
@property(copy,readonly)	NSString*				backupPath;
@property(retain,readwrite)	id<LogConvertDelegate>	delegate;

// ファクトリ
+ (id)converter;

// 変換
- (BOOL)needConversion;
- (BOOL)backup;
- (BOOL)convertToUTF8:(NSWindow*)aModalWindow;

@end
