/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AttachmentFile.m
 *	Module		: 添付ファイルオブジェクトクラス
 *============================================================================*/

//	#define IPMSG_LOG_TRC	0

#import "AttachmentFile.h"
#import "IPMessenger.h"
#import "NSStringIPMessenger.h"
#import "DebugLog.h"

/*============================================================================*
 * プライベートメソッド定義
 *============================================================================*/

@interface AttachmentFile()
- (id)initWithBuffer:(NSString*)buf needReadModTime:(BOOL)flag;
- (void)readExtendAttribute:(NSString*)str;
- (NSMutableDictionary*)fileAttributes;
@property(assign,readwrite)	NSString*	name;
@property(assign,readwrite)	NSString*	path;
@property(assign,readwrite)	UInt64		size;
@property(assign,readwrite)	UInt32		attribute;
@property(retain,readwrite)	NSDate*		createTime;
@property(retain,readwrite)	NSDate*		modifyTime;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation AttachmentFile

@synthesize name		= _name;
@synthesize path		= _path;
@synthesize size		= _size;
@synthesize attribute	= _attribute;
@synthesize createTime	= _createTime;
@synthesize modifyTime	= _modifyTime;

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

+ (id)fileWithPath:(NSString*)path {
	return [[[AttachmentFile alloc] initWithPath:path] autorelease];
}

+ (id)fileWithDirectory:(NSString*)dir file:(NSString*)file {
	return [[[AttachmentFile alloc] initWithDirectory:dir file:file] autorelease];
}

+ (id)fileWithMessage:(NSString*)str {
	return [[[AttachmentFile alloc] initWithMessage:str] autorelease];
}

+ (id)fileWithDirectory:(NSString*)dir header:(NSString*)header {
	return [[[AttachmentFile alloc] initWithDirectory:dir header:header] autorelease];
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化（送信メッセージ添付ファイル用）
- (id)initWithPath:(NSString*)path {
	NSFileManager*	fileManager;
	NSDictionary*	attrs;
	NSString*		work;
	NSRange			range;

	self			= [super init];
	_nameEscaped	= nil;
	hfsFileType		= 0;
	hfsCreator		= 0;
	permission		= 0;
	handle			= nil;

	fileManager = [NSFileManager defaultManager];
	// ファイル存在チェック
	if (![fileManager fileExistsAtPath:path]) {
		ERR(@"file not exists(%@)", path);
		[self release];
		return nil;
	}
	// ファイル読み込みチェック
	if (![fileManager isReadableFileAtPath:path]) {
		ERR(@"file not readable(%@)", path);
		[self release];
		return nil;
	}
	// ファイル属性取得
	attrs = [fileManager attributesOfItemAtPath:path error:NULL];
	// 初期化
	NSMutableString* uncomp = [NSMutableString stringWithString:[path lastPathComponent]];
	CFStringNormalize((CFMutableStringRef)uncomp, kCFStringNormalizationFormC);
	self.name		= [[NSString alloc] initWithString:uncomp];
	self.path		= [path copy];
	self.size		= [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
	self.createTime	= [attrs objectForKey:NSFileCreationDate];
	self.modifyTime	= [attrs objectForKey:NSFileModificationDate];

	permission	= [[attrs objectForKey:NSFilePosixPermissions] unsignedIntValue];
	hfsFileType	= [[attrs objectForKey:NSFileHFSTypeCode] unsignedLongValue];
	hfsCreator	= [[attrs objectForKey:NSFileHFSCreatorCode] unsignedLongValue];
	// 初期化（fileAttribute)
	work = [attrs objectForKey:NSFileType];
	if ([work isEqualToString:NSFileTypeRegular]) {
		self.attribute	= IPMSG_FILE_REGULAR;
	} else if ([work isEqualToString:NSFileTypeDirectory]) {
		self.attribute	= IPMSG_FILE_DIR;
		self.size		= 0LL;	// 0じゃない場合があるみたいなので
	} else {
		WRN(@"filetype unsupported(%@ is %@)", self.path, work);
		[self release];
		return nil;
	}
	if ([[attrs objectForKey:NSFileExtensionHidden] boolValue]) {
		self.attribute |= IPMSG_FILE_EXHIDDENOPT;
	}
	if ([[attrs objectForKey:NSFileImmutable] boolValue]) {
		self.attribute |= IPMSG_FILE_RONLYOPT;
	}
	NSURL* fileURL = [NSURL fileURLWithPath:path];
	id value;
	if ([fileURL getResourceValue:&value forKey:NSURLIsAliasFileKey error:NULL]) {
		if ([value boolValue]) {
			// エイリアスファイルは除く
			ERR(@"file is hfs Alias(%@)", self.path);
			[self release];
			return nil;
		}
	}
	if ([fileURL getResourceValue:&value forKey:NSURLIsSymbolicLinkKey error:NULL]) {
		if ([value boolValue]) {
			// シンボリックリンクは除く
			ERR(@"file is Symbolic link(%@)", self.path);
			[self release];
			return nil;
		}
	}
	if ([fileURL getResourceValue:&value forKey:NSURLIsHiddenKey error:NULL]) {
		if ([value boolValue]) {
			// 非表示ファイル
			self.attribute |= IPMSG_FILE_HIDDENOPT;
		}
	}
	// ファイル名エスケープ（":"→"::"）
	range = [self.name rangeOfString:@":"];
	if (range.location != NSNotFound) {
		NSMutableString*	escaped	= [NSMutableString stringWithCapacity:[self.name length] + 10];
		NSArray*			array	= [self.name componentsSeparatedByString:@":"];
		unsigned			i;
		for (i = 0; i < [array count]; i++) {
			if (i != 0) {
				[escaped appendString:@"::"];
			}
			[escaped appendString:[array objectAtIndex:i]];
		}
		_nameEscaped = [[NSString alloc] initWithString:escaped];
	} else {
		_nameEscaped = [self.name retain];
	}

	return self;
}

// 初期化（送信ディレクトリ内の個別ファイル）
- (id)initWithDirectory:(NSString*)dir file:(NSString*)file {
	return [self initWithPath:[dir stringByAppendingPathComponent:file]];
}

// 初期化（受信メッセージの添付ファイル）
- (id)initWithMessage:(NSString*)str
{
	return [self initWithBuffer:str needReadModTime:YES];
}

// 初期化（ディレクトリ添付ファイル内の個別ファイル）
- (id)initWithDirectory:(NSString*)dir header:(NSString*)header {
	self = [self initWithBuffer:header needReadModTime:NO];
	if (self) {
		// ファイルパス
		if ([self isParentDirectory]) {
			self.path = [[dir stringByDeletingLastPathComponent] retain];
		} else {
			self.path = [[dir stringByAppendingPathComponent:self.name] retain];
		}
	}
	return self;
}

// 解放
- (void)dealloc {
	[_name release];
	[_nameEscaped release];
	[_path release];
	[_createTime release];
	[_modifyTime release];

	[handle release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * getter/setter
 *----------------------------------------------------------------------------*/

// 通常ファイル判定
- (BOOL)isRegularFile {
	return (GET_MODE(self.attribute) == IPMSG_FILE_REGULAR);
}

// ディレクトリ判定
- (BOOL)isDirectory {
	return (GET_MODE(self.attribute) == IPMSG_FILE_DIR);
}

// 親ディレクトリ判定
- (BOOL)isParentDirectory {
	return (GET_MODE(self.attribute) == IPMSG_FILE_RETPARENT);
}

// 拡張子非表示判定
- (BOOL)isExtensionHidden {
	return ((self.attribute & IPMSG_FILE_EXHIDDENOPT) != 0);
}

// ディレクトリ設定（ファイル保存時）
- (void)setDirectory:(NSString*)dir {
	if (self.path) {
		ERR(@"filePath already exist(%@,dir=%@)", self.path, dir);
		return;
	}
	self.path = [[dir stringByAppendingPathComponent:self.name] retain];
}

/*----------------------------------------------------------------------------*
 * アイコン関連
 *----------------------------------------------------------------------------*/

- (NSImage*)iconImage {
	NSWorkspace* ws = [NSWorkspace sharedWorkspace];
	// 絶対パス（ローカルファイル）
	if ([self.path isAbsolutePath]) {
		return [ws iconForFile:self.path];
	}
	// ディレクトリ
	if ([self isDirectory]) {
		if ([[self.name pathExtension] isEqualToString:@"app"]) {
			return [ws iconForFileType:@"app"];
		}
		return [ws iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)];
	}
	// ファイルタイプあり
	if (hfsFileType != 0) {
		return [ws iconForFileType:NSFileTypeForHFSTypeCode(hfsFileType)];
	}
	// 最後のたのみ拡張子
	return [ws iconForFileType:[self.name pathExtension]];
}

/*----------------------------------------------------------------------------*
 * ファイル入出力関連
 *----------------------------------------------------------------------------*/

// ファイル存在チェック
- (BOOL)isFileExists {
	return [[NSFileManager defaultManager] fileExistsAtPath:self.path];
}

// 書き込み用に開く
- (BOOL)openFileForWrite {
	NSFileManager* fileManager = [NSFileManager defaultManager];

	if (handle) {
		// 既に開いていれば閉じる（バグ）
		WRN(@"openToRead:Recalled(%@)", self.path);
		[handle closeFile];
		[handle release];
		handle = nil;
	}

	if (!self.path) {
		// ファイルパス未定義は受信添付ファイルの場合ありえる（バグ）
		ERR(@"filePath not specified.(%@)", self.name);
		return NO;
	}

	switch (GET_MODE(self.attribute)) {
	case IPMSG_FILE_REGULAR:	// 通常ファイル
//		DBG(@"type[file]=%@,size=%d", self.name, fileSize);
		// 既存ファイルがあれば削除
		if ([fileManager fileExistsAtPath:self.path]) {
			if (![fileManager removeItemAtPath:self.path error:NULL]) {
				ERR(@"remove error exist file(%@)", self.path);
				NSRunAlertPanel(NSLocalizedString(@"RecvDlg.Attach.NoPermission.Title", nil),
								NSLocalizedString(@"RecvDlg.Attach.NoPermission.Msg", nill),
								NSLocalizedString(@"RecvDlg.Attach.NoPermission.OK", nil),
								nil, nil, self.path);
			}
		}
		// ファイル作成
		if (![fileManager createFileAtPath:self.path
								  contents:nil
								attributes:[self fileAttributes]]) {
			ERR(@"file create error(%@)", self.path);
			return NO;
		}
		// オープン（サイズ０は除く）
		if (self.size > 0) {
			handle = [[NSFileHandle fileHandleForWritingAtPath:self.path] retain];
			if (!handle) {
				ERR(@"file open error(%@)", self.path);
				return NO;
			}
		}
		break;
	case IPMSG_FILE_DIR:		// 子ディレクトリ
//		DBG(@"type[subDir]=%@", self.name);
		// 既存ファイルがあれば削除
		if ([fileManager fileExistsAtPath:self.path]) {
			if (![fileManager removeItemAtPath:self.path error:NULL]) {
				ERR(@"remove error exist dir(%@)", self.path);
				NSRunAlertPanel(NSLocalizedString(@"RecvDlg.Attach.NoPermission.Title", nil),
								NSLocalizedString(@"RecvDlg.Attach.NoPermission.Msg", nill),
								NSLocalizedString(@"RecvDlg.Attach.NoPermission.OK", nil),
								nil, nil, self.path);
			}
		}
		// ディレクトリ作成
		if (![fileManager createDirectoryAtPath:self.path
					withIntermediateDirectories:YES
									 attributes:[self fileAttributes]
										  error:NULL]) {
				  ERR(@"dir create error(%@)", self.path);
			return NO;
		}
		break;
	case IPMSG_FILE_RETPARENT:	// 親ディレクトリ
//		DBG(@"dir:type[parentDir]=%@", self.name);
		break;
	case IPMSG_FILE_SYMLINK:	// シンボリックリンク
		WRN(@"dir:type[symlink] not support.(%@)", self.name);
		break;
	case IPMSG_FILE_CDEV:		// キャラクタ特殊ファイル
		WRN(@"dir:type[cdev] not support.(%@)", self.name);
		break;
	case IPMSG_FILE_BDEV:		// ブロック特殊ファイル
		WRN(@"dir:type[bdev] not support.(%@)", self.name);
		break;
	case IPMSG_FILE_FIFO:		// FIFOファイル
		WRN(@"dir:type[fifo] not support.(%@)", self.name);
		break;
	case IPMSG_FILE_RESFORK:	// リソースフォーク
// リソースフォーク対応時に修正が必要
		WRN(@"dir:type[resfork] not support yet.(%@)", self.name);
		break;
	default:					// 未知
		WRN(@"dir:unknown type(%@,attr=0x%08X)", self.name, (unsigned int)self.attribute);
		break;
	}

	return YES;
}

// ファイル書き込み
- (BOOL)writeData:(void*)data length:(unsigned)len
{
	if (!handle) {
		ERR(@"handle not opend.");
		return NO;
	}
	@try {
		[handle writeData:[NSData dataWithBytesNoCopy:data length:len freeWhenDone:NO]];
		return YES;
	}
	@catch (NSException* exception) {
		ERR(@"write error([%@]size=%u)", [exception name], len);
	}
	return NO;
}

// ファイルクローズ
- (void)closeFile {
	if (handle) {
		[handle closeFile];
		[handle release];
		handle = nil;
	}
	if ([self isRegularFile] || [self isDirectory]) {
		NSFileManager*			fileManager;
		NSDictionary*			orgDic;
		NSMutableDictionary*	newDic;
		// FileManager属性の設定
		fileManager = [NSFileManager defaultManager];
		orgDic		= [fileManager attributesOfItemAtPath:self.path error:NULL];
		newDic		= [NSMutableDictionary dictionaryWithCapacity:[orgDic count]];
		[newDic addEntriesFromDictionary:orgDic];
		[newDic addEntriesFromDictionary:[self fileAttributes]];
		[newDic setObject:[NSNumber numberWithBool:((self.attribute&IPMSG_FILE_RONLYOPT) != 0)] forKey:NSFileImmutable];
		[fileManager setAttributes:newDic ofItemAtPath:self.path error:NULL];
		if (self.attribute & IPMSG_FILE_HIDDENOPT) {
			NSURL* fileURL = [NSURL fileURLWithPath:self.path];
			NSError* error = nil;
			if (![fileURL setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsHiddenKey error:&error]) {
				ERR(@"Hidden set error(%@,%@)", self.path, error);
			}
		}
	}
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

// オブジェクト概要
- (NSString*)description {
	return [NSString stringWithFormat:@"AttachmentFile[%@(size=%llX)]", self.name, self.size];
}

/*----------------------------------------------------------------------------*
 * 内部処理（Private）
 *----------------------------------------------------------------------------*/

// 受信バッファ解析初期化共通処理
- (id)initWithBuffer:(NSString*)buf needReadModTime:(BOOL)flag
{
	self			= [super init];
	_nameEscaped	= nil;
	hfsFileType		= 0;
	hfsCreator		= 0;
	permission		= 0;
	handle			= nil;

	/*------------------------------------------------------------------------*
	 * ファイル名
	 *------------------------------------------------------------------------*/

	@try {
		NSRange	range = [buf rangeOfString:@":"];
		if (range.location == NSNotFound) {
			ERR(@"file name error(%@)", buf);
			[self release];
			return nil;
		}
		while ([buf characterAtIndex:range.location + 1] == ':') {
			NSRange work = range;
			work.location += 2;
			work.length = [buf length] - work.location;
			range = [buf rangeOfString:@":" options:0 range:work];
		}
		NSString* name;
		// ファイル名部分を切り出す
		_nameEscaped	= [buf substringToIndex:range.location];
		// 解析対象文字列をファイル名の後からにする
		buf	= [buf substringFromIndex:range.location + 1];
		// ファイル名の"::"エスケープを"_"にする（:はファイルパスに使えないので）
		self.name = [_nameEscaped stringByReplacingOccurrencesOfString:@"::" withString:@"_"];
		// ファイル名の"/"を"_"にする（HFS+ならば"/"は使えるが、HFS+以外の場合や混乱を回避するため）
		self.name = [self.name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

		[_nameEscaped retain];
		[self.name retain];
	}
	@catch (NSException* exception) {
		ERR(@"file name error(%@,exp=%@)", buf, exception);
		[self release];
		return nil;
	}
	TRC(@"fileName:%@(escaped:%@)", self.name, _nameEscaped);

	NSArray*	strs	= [buf componentsSeparatedByString:@":"];
	NSInteger	index	= 0;
	NSString*	str;
	NSScanner*	scanner;
	UInt		uintVal;
	UInt64		uint64Val;

	/*------------------------------------------------------------------------*
	 * ファイルサイズ
	 *------------------------------------------------------------------------*/

	str		= [strs objectAtIndex:index];
	scanner	= [NSScanner scannerWithString:str];
	if (![scanner scanHexLongLong:&uint64Val]) {
		ERR(@"file size error(%@)", str);
		[self release];
		return nil;
	}
	self.size = uint64Val;
	index++;
	TRC(@"fileSize:%lld", self.size);

	/*------------------------------------------------------------------------*
	 * 更新時刻（MessageAttachmentのみ）
	 *------------------------------------------------------------------------*/

	if (flag) {
		str		= [strs objectAtIndex:index];
		scanner = [NSScanner scannerWithString:str];
		if (![scanner scanHexInt:&uintVal]) {
			ERR(@"modDate attr error(%@)", str);
			[self release];
			return nil;
		}
		self.modifyTime = [NSDate dateWithTimeIntervalSince1970:uintVal];
		index++;
		TRC(@"modTime:%@", self.modifyTime);
	}

	/*------------------------------------------------------------------------*
	 * ファイル属性
	 *------------------------------------------------------------------------*/

	str		= [strs objectAtIndex:index];
	scanner = [NSScanner scannerWithString:str];
	if (![scanner scanHexInt:&uintVal]) {
		ERR(@"file attr error(%@)", str);
		[self release];
		return nil;
	}
	self.attribute = uintVal;
	index++;
	TRC(@"attr:0x%08X", self.attribute);

	/*------------------------------------------------------------------------*
	 * 拡張ファイル属性
	 *------------------------------------------------------------------------*/

	while (index < [strs count]) {
		str	= [strs objectAtIndex:index];
		[self readExtendAttribute:str];
		index++;
	}

	return self;
}

// 拡張ファイル属性編集
- (NSString*)makeExtendAttribute
{
	NSMutableArray* array = [NSMutableArray arrayWithCapacity:10];
	if (self.createTime) {
		unsigned val = (unsigned)[self.createTime timeIntervalSince1970];
		[array addObject:[NSString stringWithFormat:@"%lX=%X", IPMSG_FILE_CREATETIME, val]];
	}
	if (self.modifyTime) {
		unsigned val = (unsigned)[self.modifyTime timeIntervalSince1970];
		[array addObject:[NSString stringWithFormat:@"%lX=%X", IPMSG_FILE_MTIME, val]];
	}
	if (permission != 0) {
		[array addObject:[NSString stringWithFormat:@"%lX=%X", IPMSG_FILE_PERM, permission]];
	}
	if (hfsFileType != 0) {
		[array addObject:[NSString stringWithFormat:@"%lX=%X", IPMSG_FILE_FILETYPE, (unsigned int)hfsFileType]];
	}
	if (hfsCreator != 0) {
		[array addObject:[NSString stringWithFormat:@"%lX=%X", IPMSG_FILE_CREATOR, (unsigned int)hfsCreator]];
	}
	if ([array count] > 0) {
		return [array componentsJoinedByString:@":"];
	}
	return @"";
}

// 拡張ファイル属性解析
- (void)readExtendAttribute:(NSString*)str
{
	UInt		key;
	UInt		val;
	NSScanner*	scanner;
	NSArray*	kv	= [str componentsSeparatedByString:@"="];

	TRC(@"extAttr:string='%@'", str);
	if ([str length] <= 0) {
		TRC(@"extAttr:skip empty");
		return;
	}

	if ([kv count] != 2) {
		ERR(@"extend attribute invalid(%@)", str);
		return;
	}

	scanner	= [NSScanner scannerWithString:[kv objectAtIndex:0]];
	if (![scanner scanHexInt:&key]) {
		ERR(@"extend attribute invalid(%@)", str);
		return;
	}
	scanner	= [NSScanner scannerWithString:[kv objectAtIndex:1]];
	if (![scanner scanHexInt:&val]) {
		ERR(@"extend attribute invalid(%@)", str);
		return;
	}

	switch (key) {
		case IPMSG_FILE_UID:
			WRN(@"extAttr:UID          unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_USERNAME:
			WRN(@"extAttr:USERNAME     unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_GID:
			WRN(@"extAttr:GID          unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_GROUPNAME:
			WRN(@"extAttr:GROUPNAME    unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_CLIPBOARDPOS:
			WRN(@"extAttr:CLIPBOARDPOS unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_PERM:
			permission = val;
			TRC(@"extAttr:PERM       = 0%03o", permission);
			break;
		case IPMSG_FILE_MAJORNO:
			WRN(@"extAttr:MAJORNO      unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_MINORNO:
			WRN(@"extAttr:MINORNO      unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_CTIME:
			WRN(@"extAttr:CTIME        unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_MTIME:
			self.modifyTime = [NSDate dateWithTimeIntervalSince1970:val];
			TRC(@"extAttr:MTIME      = %d(%@)", val, self.modifyTime);
			break;
		case IPMSG_FILE_ATIME:
			WRN(@"extAttr:ATIME        unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_CREATETIME:
			self.createTime = [NSDate dateWithTimeIntervalSince1970:val];
			TRC(@"extAttr:CREATETIME = %d(%@)", val, self.createTime);
			break;
		case IPMSG_FILE_CREATOR:
			hfsCreator = val;
			TRC(@"extAttr:CREATOR    = 0x%08X('%c%c%c%c')", hfsCreator,
										((char*)&val)[0], ((char*)&val)[1],
										((char*)&val)[2], ((char*)&val)[3]);
			break;
		case IPMSG_FILE_FILETYPE:
			hfsFileType = val;
			TRC(@"extAttr:FILETYPE   = 0x%08X('%c%c%c%c')", hfsFileType,
										((char*)&val)[0], ((char*)&val)[1],
										((char*)&val)[2], ((char*)&val)[3]);
			break;
		case IPMSG_FILE_FINDERINFO:
			WRN(@"extAttr:FINDERINFO   unsupported(0x%04X['%c%c'])", val,
										((char*)&val)[0], ((char*)&val)[1]);
			break;
		case IPMSG_FILE_ACL:
			WRN(@"extAttr:ACL          unsupported(%d[0x%X])", val, val);
			break;
		case IPMSG_FILE_ALIASFNAME:
			WRN(@"extAttr:ALIASFNAME   unsupported(%d[0x%X])", val, val);
			break;
		default:
			WRN(@"extAttr:unknownType(key=0x%08X,val=%d[0x%X])", key, val, val);
			break;
	}
}

// ファイル属性（NSFileManager用）作成
- (NSMutableDictionary*)fileAttributes
{
	NSMutableDictionary* attr = [NSMutableDictionary dictionaryWithCapacity:6];

	// アクセス権（安全のため0600は必ず付与）
	if (permission != 0) {
		[attr setObject:[NSNumber numberWithUnsignedInt:(permission|0600)]
				 forKey:NSFilePosixPermissions];
	}

	// 作成日時
	if (self.createTime) {
		[attr setObject:self.createTime
				 forKey:NSFileCreationDate];
	}

	// 更新日時
	if (self.modifyTime) {
		[attr setObject:self.modifyTime
				 forKey:NSFileModificationDate];
	}

	// 拡張子非表示（ファイルの場合のみ）
	if ([self isRegularFile]) {
		[attr setObject:[NSNumber numberWithBool:((self.attribute|IPMSG_FILE_EXHIDDENOPT) != 0)]
				 forKey:NSFileExtensionHidden];
	}

	// ファイルタイプ
	if (hfsFileType != 0) {
		[attr setObject:[NSNumber numberWithUnsignedLong:hfsFileType]
				 forKey:NSFileHFSTypeCode];
	}

	// クリエータ
	if (hfsCreator != 0) {
		[attr setObject:[NSNumber numberWithUnsignedLong:hfsCreator]
				 forKey:NSFileHFSCreatorCode];
	}

	return attr;
}

@end
