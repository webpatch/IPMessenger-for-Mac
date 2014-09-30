/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AttachmentFile.h
 *	Module		: 添付ファイルオブジェクトクラス
 *============================================================================*/

#import <Cocoa/Cocoa.h>

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface AttachmentFile : NSObject
{
	NSString*		_name;
	NSString*		_nameEscaped;
	NSString*		_path;
	UInt64			_size;
	UInt32			_attribute;
	NSDate*			_createTime;
	NSDate*			_modifyTime;

	OSType				hfsFileType;		// ファイルタイプ
	OSType				hfsCreator;			// クリエータコード
	unsigned			permission;			// POSIXファイルアクセス権
	NSFileHandle*		handle;				// 出力ハンドル
}

@property(readonly)			NSString*	name;			// ファイル名
@property(readonly)			NSString*	path;			// ファイルパス
@property(readonly)			UInt64		size;			// ファイルサイズ
@property(readonly)			UInt32		attribute;		// ファイル属性(IPMsg形式)
@property(retain,readonly)	NSDate*		createTime;		// ファイル生成時刻
@property(retain,readonly)	NSDate*		modifyTime;		// ファイル最終更新時刻(mtime)

// ファクトリ
+ (id)fileWithPath:(NSString*)path;
+ (id)fileWithDirectory:(NSString*)dir file:(NSString*)file;
+ (id)fileWithMessage:(NSString*)str;
+ (id)fileWithDirectory:(NSString*)dir header:(NSString*)header;

// 初期化
- (id)initWithPath:(NSString*)path;
- (id)initWithDirectory:(NSString*)dir file:(NSString*)file;
- (id)initWithMessage:(NSString*)str;
- (id)initWithDirectory:(NSString*)dir header:(NSString*)header;

// getter/setter
- (BOOL)isRegularFile;
- (BOOL)isDirectory;
- (BOOL)isParentDirectory;
- (BOOL)isExtensionHidden;
- (void)setDirectory:(NSString*)dir;

// アイコン
- (NSImage*)iconImage;

// ファイル入出力関連
- (BOOL)isFileExists;
- (BOOL)openFileForWrite;
- (BOOL)writeData:(void*)data length:(unsigned)len;
- (void)closeFile;

// 添付処理関連
- (NSString*)makeExtendAttribute;

@end
