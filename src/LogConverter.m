/*============================================================================*
 * (C) 2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: LogConverter.m
 *	Module		: ログファイル変換（SJIS→UTF-8）
 *============================================================================*/

#import "LogConverter.h"
#import "DebugLog.h"

@interface LogConverter()
@property(copy,readwrite) NSString*	backupPath;
@end


/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation LogConverter

@synthesize name		= _name;
@synthesize path		= _path;
@synthesize backupPath	= _backupPath;
@synthesize delegate	= _delegate;

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

+ (id)converter
{
	return [[[LogConverter alloc] init] autorelease];
}

/*----------------------------------------------------------------------------*
 * 初期化/終了
 *----------------------------------------------------------------------------*/

- (id)init
{
	self = [super init];
	if (self) {
		const Byte bom[] = { 0xEF, 0xBB, 0xBF };
		self.name		= @"<Unknown>";
		_fileManager	= [[NSFileManager alloc] init];
		_bom			= [[NSData alloc] initWithBytes:bom length:sizeof(bom)];
	}

	return self;
}

- (void)dealloc
{
	[_name release];
	[_path release];
	[_backupPath release];
	[_fileManager release];
	[_bom release];
	[_delegate release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * 変換
 *----------------------------------------------------------------------------*/

// UTF-8未変換判定
- (BOOL)needConversion
{
	// 本メソッドの目的は、UTF-8変換が必要なログファイルであるかを判定すること
	TRC(@"Start check UTF-8 converted(%@,%@)", self.name, self.path);

	if (!self.path) {
		// ログファイルが指定されていなければOK
		TRC(@"LogFile not defined");
		return NO;
	}
	if (![_fileManager fileExistsAtPath:self.path]) {
		// ログファイルが存在しなければ変換できないのでOK
		TRC(@"LogFile not exist");
		return NO;
	}
	if (![_fileManager isReadableFileAtPath:self.path]) {
		// 読めないので変換できないからOK
		WRN(@"LogFile not readable(%@)", self.path);
		return NO;
	}
	NSFileHandle* file = [NSFileHandle fileHandleForReadingAtPath:self.path];
	if (!file) {
		ERR(@"LogFile open Error.(%@)", self.path);
		return NO;
	}

	// 先頭BOMチェック
	BOOL	flag = NO;
	NSData* data = [file readDataOfLength:3];
	TRC(@"LogFile read(%@)", data);
	if ([data length] > 0) {
		if (![data isEqualToData:_bom]) {
			WRN(@"LogFile may be encoded with SJIS(%@)", self.path);
			flag = YES;
		} else {
			// UTF-8 BOMが先頭にあるので変換済み
			TRC(@"LogFile contains UTF-8 BOM");
		}
	} else {
		TRC(@"LogFile is empty");
	}

	[file closeFile];

	TRC(@"Judgement is %s(%@)", (flag ? "YES" : "NO"), self.path);

	return flag;
}

// ファイルバックアップ
- (BOOL)backup
{
	TRC(@"make backup filename");
	NSString* bakPath = [self.path stringByAppendingPathExtension:@"bak"];
	while ([_fileManager fileExistsAtPath:bakPath]) {
		bakPath = [bakPath stringByAppendingPathExtension:@"bak"];
	}
	TRC(@"  -> succeeded(%@)", bakPath);

	TRC(@"rename file (%@ -> %@)", self.path, bakPath);
	[_fileManager moveItemAtPath:self.path toPath:bakPath error:NULL];

	self.backupPath = bakPath;

	return YES;
}

// 変換処理
- (BOOL)convertToUTF8:(NSWindow*)aModalWindow
{
	NSModalSession session;

	if (aModalWindow) {
		session = [NSApp beginModalSessionForWindow:aModalWindow];
		[NSApp runModalSession:session];
	}

	TRC(@"Start parepare(%@)", self.path);
	[self.delegate logConverter:self prepare:self.path];

	// ファイル読み込み
	NSError*	error = NULL;
	NSString*	content;
	TRC(@"load original file(%@)", self.path);
	content = [NSString stringWithContentsOfFile:self.path
										encoding:NSShiftJISStringEncoding
										   error:&error];
	if (!content) {
		ERR(@"load error(SJIS/%@,%@)", error, self.path);
		// 念のためUTF-8でトライ
		content = [NSString stringWithContentsOfFile:self.path
											encoding:NSUTF8StringEncoding
											   error:&error];		
		if (!content) {
			ERR(@"load error(UTF8/%@,%@)", error, self.path);
			[self.delegate logConverter:self finish:NO];
			if (aModalWindow) {
				[NSApp endModalSession:session];
			}
			return NO;
		}
	}
	TRC(@"  -> succeeded");
	if (aModalWindow) {
		[NSApp runModalSession:session];
	}

	// 行分解
	NSArray*		lines;
	NSRange			range = [content rangeOfString:@"\r\n"];
	NSCharacterSet* nrSet = [NSCharacterSet newlineCharacterSet];
	if (range.location != NSNotFound) {
		TRC(@"separate lines (CR+LF)");
		lines = [content componentsSeparatedByString:@"\r\n"];
		TRC(@"  -> CR + LF lines=%d", [lines count]);
		// 一部だけCR+LFの場合があるのでさらに分解
		NSMutableArray* work = [NSMutableArray array];
		for (NSString* line in lines) {
			[work addObjectsFromArray:[line componentsSeparatedByCharactersInSet:nrSet]];
		}
		lines = [NSArray arrayWithArray:work];
		TRC(@"  -> CR | LF lines=%d", [lines count]);
	} else {
		TRC(@"separate lines (CR or LF)");
		lines = [content componentsSeparatedByCharactersInSet:nrSet];
	}
	NSUInteger	total	= [lines count];
	NSUInteger	step	= 0;
	TRC(@"  -> succeeded(%d lines)", total);
	if (aModalWindow) {
		[NSApp runModalSession:session];
	}

	// 一時ファイルバス決定
	TRC(@"make temporary filename");
	NSString* newPath = [self.path stringByAppendingPathExtension:@"convertwork"];
	while ([_fileManager fileExistsAtPath:newPath]) {
		newPath	= [newPath stringByAppendingPathExtension:@"new"];
	}
	TRC(@"  -> succeeded(%@)", newPath);

	// 一時ファイル作成
	TRC(@"carete temporary file");
	if (![_fileManager createFileAtPath:newPath contents:_bom attributes:nil]) {
		ERR(@"temporary file create error(%@)", newPath);
		[self.delegate logConverter:self finish:NO];
		if (aModalWindow) {
			[NSApp endModalSession:session];
		}
		return NO;
	}
	TRC(@"  -> succeeded");

	// 一時ファイルオープン
	TRC(@"open temporary file");
	NSFileHandle* file = [NSFileHandle fileHandleForWritingAtPath:newPath];
	if (!file) {
		ERR(@"temporary file open error(%@)", newPath);
		[self.delegate logConverter:self finish:NO];
		[_fileManager removeItemAtPath:newPath error:NULL];
		if (aModalWindow) {
			[NSApp endModalSession:session];
		}
		return NO;
	}
	TRC(@"  -> succeeded");

	TRC(@"seek temporary file to EOF");
	[file seekToEndOfFile];
	TRC(@"  -> succeeded");

	// 変換
	TRC(@"start convert");
	[self.delegate logConverter:self start:total];
	NSDate*			start	= [NSDate date];
	NSTimeInterval	nextInt	= 0;
	NSData*			newLine	= [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
	for (NSString* line in lines) {
		[file writeData:[line dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
		[file writeData:newLine];
		if (aModalWindow) {
			NSTimeInterval interval = [start timeIntervalSinceNow];
			if (interval < nextInt) {
				[self.delegate logConverter:self progress:step];
				[NSApp runModalSession:session];
				nextInt -= 0.1;	// 0.1秒毎にコールバックとrunModalSession
			}
		}
		step++;
	}
	[file closeFile];
	TRC(@"  -> completed");

	// バックアップ
	TRC(@"make backup filename");
	NSString* bakPath = [self.path stringByAppendingPathExtension:@"bak"];
	while ([_fileManager fileExistsAtPath:bakPath]) {
		bakPath = [bakPath stringByAppendingPathExtension:@"bak"];
	}
	TRC(@"  -> succeeded(%@)", bakPath);

	TRC(@"rename file (%@ -> %@)", self.path, bakPath);
	[_fileManager moveItemAtPath:self.path toPath:bakPath error:NULL];
	TRC(@"rename file (%@ -> %@)", newPath, self.path);
	[_fileManager moveItemAtPath:newPath toPath:self.path error:NULL];
	self.backupPath	= bakPath;

	TRC(@"Finish convert(%@)", self.path);
	[self.delegate logConverter:self finish:YES];

	if (aModalWindow) {
		[NSApp endModalSession:session];
	}

	return YES;
}

@end
