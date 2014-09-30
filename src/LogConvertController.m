/*============================================================================*
 * (C) 2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: LogConvertController.m
 *	Module		: ログ変換ダイアログコントローラクラス
 *============================================================================*/

#import "LogConvertController.h"
#import "DebugLog.h"

@interface LogConvertController()
@property(retain,readwrite)	NSString*	lines;
@property(retain,readwrite)	NSString*	remainTime;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation LogConvertController

@synthesize filePath	= _filePath;
@synthesize lines		= _lines;
@synthesize remainTime	= _remain;

/*----------------------------------------------------------------------------*
 * 初期化/終了
 *----------------------------------------------------------------------------*/

- (id)init
{
	self = [self initWithWindowNibName:@"LogConvertDialog"];
	if (self) {
		self.lines			= @"-";
		self.remainTime		= @"--:--";
		[[self window] center];
	}

	return self;
}

- (void)dealloc
{
	[_filePath release];
	[_start release];
	[_lines release];
	[_remain release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * <NSNibAwaking>
 *----------------------------------------------------------------------------*/

- (void)awakeFromNib
{
	[_progressBar setIndeterminate:YES];
	[_progressBar setUsesThreadedAnimation:YES];
	[_indicator setUsesThreadedAnimation:YES];
}

/*----------------------------------------------------------------------------*
 * <LogConvertDelegate>
 *----------------------------------------------------------------------------*/

- (void)logConverter:(LogConverter*)aConverter prepare:(NSString*)aFilePath
{
	[_progressBar startAnimation:self];
	[_indicator startAnimation:self];
}

- (void)logConverter:(LogConverter*)aConverter start:(NSUInteger)aTotalStep
{
	_start		= [[NSDate alloc] init];
	_totalStep	= aTotalStep;
	self.lines	= [NSString stringWithFormat:@"0 / %d", _totalStep];
	[_progressBar setMaxValue:aTotalStep];
	[_progressBar setDoubleValue:0];
	[_progressBar setIndeterminate:NO];
}

- (void)logConverter:(LogConverter*)aConverter progress:(NSUInteger)aStep
{
	NSTimeInterval	interval	= -[_start timeIntervalSinceNow];
	NSUInteger		remainStep	= _totalStep - aStep;
	double			stepPerSec	= (double)aStep / interval;
	NSInteger		remainSec	= (NSInteger)((double)remainStep / stepPerSec) + 1;
	self.lines		= [NSString stringWithFormat:@"%d / %d", aStep, _totalStep];
	self.remainTime	= [NSString stringWithFormat:@"%d:%02d", remainSec / 60, remainSec % 60];
	[_progressBar setDoubleValue:aStep];
}

- (void)logConverter:(LogConverter*)aConverter finish:(BOOL)aResult
{
}

@end
