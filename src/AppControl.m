/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AppControl.m
 *	Module		: アプリケーションコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import "AppControl.h"
#import "Config.h"
#import "MessageCenter.h"
#import "AttachmentServer.h"
#import "RecvMessage.h"
#import "ReceiveControl.h"
#import "SendControl.h"
#import "NoticeControl.h"
#import "WindowManager.h"
#import "LogConverter.h"
#import "LogConvertController.h"
#import "UserInfo.h"
#import "DebugLog.h"

#define ABSENCE_OFF_MENU_TAG	1000
#define ABSENCE_ITEM_MENU_TAG	2000

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation AppControl

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)init
{
	self = [super init];
	if (self) {
		NSBundle* bundle = [NSBundle mainBundle];
		receiveQueue			= [[NSMutableArray alloc] init];
		receiveQueueLock		= [[NSLock alloc] init];
		iconToggleTimer			= nil;
		iconNormal				= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"IPMsg" ofType:@"icns"]];
		iconNormalReverse		= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"IPMsgReverse" ofType:@"icns"]];
		iconAbsence				= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"IPMsgAbsence" ofType:@"icns"]];
		iconAbsenceReverse		= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"IPMsgAbsenceReverse" ofType:@"icns"]];
		lastDockDraggedDate		= nil;
		lastDockDraggedWindow	= nil;
		iconSmallNormal			= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"menu_normal" ofType:@"png"]];
		iconSmallNormalReverse	= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"menu_highlight" ofType:@"png"]];
		iconSmallAbsence		= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"menu_normal" ofType:@"png"]];
		iconSmallAbsenceReverse	= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"menu_highlight" ofType:@"png"]];
		iconSmallAlaternate		= [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"menu_alternate" ofType:@"png"]];
        lastSendMsgWindow       = nil;
	}

	return self;
}

// 解放
- (void)dealloc
{
	[receiveQueue release];
	[receiveQueueLock release];
	[iconToggleTimer release];
	[iconNormal release];
	[iconNormalReverse release];
	[iconAbsence release];
	[iconAbsenceReverse release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * メッセージ送受信／ウィンドウ関連
 *----------------------------------------------------------------------------*/

// 新邮件窗口，显示处理
- (IBAction)newMessage:(id)sender {
    BOOL isCreate = YES;
    NSArray *wins = [NSApp windows];
	for (int i = 0; i < [wins count]; i++) {
		NSWindow* win = [wins objectAtIndex:i];
        if([win.delegate isKindOfClass:[SendControl class]]||[win.delegate isKindOfClass:[ReceiveControl class]])
        {
            isCreate = NO;
            break;
        }
    }
    
	if (![NSApp isActive]) {
		activatedFlag = -1;		// アクティベートで新規ウィンドウが開いてしまうのを抑止
		[NSApp activateIgnoringOtherApps:YES];
	}
    
    if (isCreate) {
         [[SendControl alloc] initWithSendMessage:nil recvMessage:nil];
    }
}

// メッセージ受信時処理
- (void)receiveMessage:(RecvMessage*)msg {
	Config*			config	= [Config sharedConfig];
	ReceiveControl*	recv;
	// 表示中のウィンドウがある場合無視する
	if ([[WindowManager sharedManager] receiveWindowForKey:msg]) {
		WRN(@"already visible message.(%@)", msg);
		return;
	}
	// 受信音再生
	[config.receiveSound play];
	// 受信ウィンドウ生成（まだ表示しない）
	recv = [[ReceiveControl alloc] initWithRecvMessage:msg];
	if (config.nonPopup) {
		if ((config.nonPopupWhenAbsence && config.inAbsence) ||
			(!config.nonPopupWhenAbsence)) {
			// ノンポップアップの場合受信キューに追加
			[receiveQueueLock lock];
			[receiveQueue addObject:recv];
			[receiveQueueLock unlock];
			switch (config.iconBoundModeInNonPopup) {
			case IPMSG_BOUND_ONECE:
				[NSApp requestUserAttention:NSInformationalRequest];
				break;
			case IPMSG_BOUND_REPEAT:
				[NSApp requestUserAttention:NSCriticalRequest];
				break;
			case IPMSG_BOUND_NONE:
			default:
				break;
			}
			if (!iconToggleTimer) {
				// アイコントグル開始
				iconToggleState	= YES;
				iconToggleTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
																   target:self
																 selector:@selector(toggleIcon:)
																 userInfo:nil
																  repeats:YES];
			}
			return;
		}
	}
	if (![NSApp isActive]) {
		[NSApp activateIgnoringOtherApps:YES];
	}
	[recv showWindow];
}

// すべてのウィンドウを閉じる
- (IBAction)closeAllWindows:(id)sender {
	NSEnumerator*	e = [[NSApp orderedWindows] objectEnumerator];
	NSWindow*		win;
	while ((win = (NSWindow*)[e nextObject])) {
		if ([win isVisible]) {
			[win performClose:self];
		}
	}
}

// すべての通知ダイアログを閉じる
- (IBAction)closeAllDialogs:(id)sender {
	NSEnumerator*	e = [[NSApp orderedWindows] objectEnumerator];
	NSWindow*		win;
	while ((win = (NSWindow*)[e nextObject])) {
		if ([[win delegate] isKindOfClass:[NoticeControl class]]) {
			[win performClose:self];
		}
	}
}

/*----------------------------------------------------------------------------*
 * 不在メニュー関連
 *----------------------------------------------------------------------------*/

- (NSMenuItem*)createAbsenceMenuItemAtIndex:(int)index state:(BOOL)state {
	NSMenuItem* item = [[[NSMenuItem alloc] init] autorelease];
	[item setTitle:[[Config sharedConfig] absenceTitleAtIndex:index]];
	[item setEnabled:YES];
	[item setState:state];
	[item setTarget:self];
	[item setAction:@selector(absenceMenuChanged:)];
	[item setTag:ABSENCE_ITEM_MENU_TAG + index];
	return item;
}

// 不在メニュー作成
- (void)buildAbsenceMenu {
	Config*		config	= [Config sharedConfig];
	int			num		= [config numberOfAbsences];
	NSInteger	index	= config.absenceIndex;
	int			i;

	// 不在モード解除とその下のセパレータ以外を一旦削除
	for (i = [absenceMenu numberOfItems] - 1; i > 1 ; i--) {
		[absenceMenu removeItemAtIndex:i];
	}
	for (i = [absenceMenuForDock numberOfItems] - 1; i > 1 ; i--) {
		[absenceMenuForDock removeItemAtIndex:i];
	}
	for (i = [absenceMenuForStatusBar numberOfItems] - 1; i > 1 ; i--) {
		[absenceMenuForStatusBar removeItemAtIndex:i];
	}
	if (num > 0) {
		for (i = 0; i < num; i++) {
			[absenceMenu addItem:[self createAbsenceMenuItemAtIndex:i state:(i == index)]];
			[absenceMenuForDock addItem:[self createAbsenceMenuItemAtIndex:i state:(i == index)]];
			[absenceMenuForStatusBar addItem:[self createAbsenceMenuItemAtIndex:i state:(i == index)]];
		}
	}
	[absenceOffMenuItem setState:(index == -1)];
	[absenceOffMenuItemForDock setState:(index == -1)];
	[absenceOffMenuItemForStatusBar setState:(index == -1)];
	[absenceMenu update];
	[absenceMenuForDock update];
	[absenceMenuForStatusBar update];
}

// 不在メニュー選択ハンドラ
- (IBAction)absenceMenuChanged:(id)sender {
	Config*		config	= [Config sharedConfig];
	NSInteger	oldIdx	= config.absenceIndex;
	int			newIdx;

	if ([sender tag] == ABSENCE_OFF_MENU_TAG) {
		newIdx = -2;
	} else {
		newIdx = [sender tag] - ABSENCE_ITEM_MENU_TAG;
	}

	// 現在選択されている不在メニューのチェックを消す
	if (oldIdx == -1) {
		oldIdx = -2;
	}
	[[absenceMenu				itemAtIndex:oldIdx + 2] setState:NSOffState];
	[[absenceMenuForDock		itemAtIndex:oldIdx + 2] setState:NSOffState];
	[[absenceMenuForStatusBar	itemAtIndex:oldIdx + 2] setState:NSOffState];

	// 選択された項目にチェックを入れる
	[[absenceMenu				itemAtIndex:newIdx + 2] setState:NSOnState];
	[[absenceMenuForDock		itemAtIndex:newIdx + 2] setState:NSOnState];
	[[absenceMenuForStatusBar	itemAtIndex:newIdx + 2] setState:NSOnState];

	// 選択された項目によってアイコンを変更する
	if (newIdx < 0) {
		[NSApp setApplicationIconImage:iconNormal];
		[statusBarItem setImage:iconSmallNormal];
	} else {
		[NSApp setApplicationIconImage:iconAbsence];
		[statusBarItem setImage:iconSmallAbsence];
	}

	[sender setState:NSOnState];

	config.absenceIndex = newIdx;
	[[MessageCenter sharedCenter] broadcastAbsence];
}

// 不在解除
- (void)setAbsenceOff {
	[self absenceMenuChanged:absenceOffMenuItem];
}

/*----------------------------------------------------------------------------*
 * ステータスバー関連
 *----------------------------------------------------------------------------*/

- (void)initStatusBar {
	if (statusBarItem == nil) {
		// ステータスバーアイテムの初期化
		statusBarItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
		[statusBarItem retain];
		[statusBarItem setTitle:@""];
		[statusBarItem setImage:iconSmallNormal];
		[statusBarItem setAlternateImage:iconSmallAlaternate];
		//[statusBarItem setMenu:statusBarMenu];
		[statusBarItem setHighlightMode:YES];
        
        statusBarItem.action = @selector(openMenu:);
        statusBarItem.target = self;
	}
}

// 点击状态栏图标
-(void)openMenu:(id)sender
{
    int 		i;
	BOOL		b;
	Config*		config = [Config sharedConfig];
    
    [receiveQueueLock lock];
	b = ([receiveQueue count] > 0);
	for (i = 0; i < [receiveQueue count]; i++) {
		[[receiveQueue objectAtIndex:i] showWindow];
	}
	[receiveQueue removeAllObjects];
	if (b && iconToggleTimer) {
		[iconToggleTimer invalidate];
		iconToggleTimer = nil;
		[NSApp setApplicationIconImage:((config.inAbsence) ? iconAbsence : iconNormal)];
		[statusBarItem setImage:((config.inAbsence) ? iconSmallAbsence : iconSmallNormal)];
	}
	[receiveQueueLock unlock];
    statusBarItem.title = @"";
    
    [self newMessage:nil];
}

- (void)removeStatusBar {
	if (statusBarItem != nil) {
		// ステータスバーアイテムを破棄
		[[NSStatusBar systemStatusBar] removeStatusItem:statusBarItem];
		[statusBarItem release];
		statusBarItem = nil;
	}
}

- (void)clickStatusBar:(id)sender{
	activatedFlag = -1;		// アクティベートで新規ウィンドウが開いてしまうのを抑止
	[NSApp activateIgnoringOtherApps:YES];
	[self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

// Webサイトに飛ぶ
- (IBAction)gotoHomePage:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:NSLocalizedString(@"IPMsg.HomePage", nil)]];
}

// 謝辞の表示
- (IBAction)showAcknowledgement:(id)sender {
	NSString* path = [[NSBundle mainBundle] pathForResource:@"Acknowledgement" ofType:@"pdf"];
	[[NSWorkspace sharedWorkspace] openFile:path];
}

// Nibファイルロード完了時
- (void)awakeFromNib {
	Config* config = [Config sharedConfig];
	// メニュー設定
	[sendWindowListUserMenuItem setState:![config sendWindowUserListColumnHidden:kIPMsgUserInfoUserNamePropertyIdentifier]];
	[sendWindowListGroupMenuItem setState:![config sendWindowUserListColumnHidden:kIPMsgUserInfoGroupNamePropertyIdentifier]];
	[sendWindowListHostMenuItem setState:![config sendWindowUserListColumnHidden:kIPMsgUserInfoHostNamePropertyIdentifier]];
	[sendWindowListIPAddressMenuItem setState:![config sendWindowUserListColumnHidden:kIPMsgUserInfoIPAddressPropertyIdentifier]];
	[sendWindowListLogonMenuItem setState:![config sendWindowUserListColumnHidden:kIPMsgUserInfoLogOnNamePropertyIdentifier]];
	[sendWindowListVersionMenuItem setState:![config sendWindowUserListColumnHidden:kIPMsgUserInfoVersionPropertyIdentifer]];
	[self buildAbsenceMenu];

	// ステータスバー
	if(config.useStatusBar){
		[self initStatusBar];
	}
}

// アプリ起動完了時処理
- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
	TRC(@"Enter");

	// 画面位置計算時の乱数初期化
	srand(time(NULL));

	// フラグ初期化
	activatedFlag = -1;

	// ログファイルのUTF-8チェック
	TRC(@"Start log check");
	Config* config = [Config sharedConfig];
	if (config.standardLogEnabled) {
		TRC(@"Need StdLog check");
		[self checkLogConversion:YES path:config.standardLogFile];
	}
	if (config.alternateLogEnabled) {
		TRC(@"Need AltLog check");
		[self checkLogConversion:NO path:config.alternateLogFile];
	}
	TRC(@"Finish log check");

	// ENTRYパケットのブロードキャスト
	TRC(@"Broadcast entry");
	[[MessageCenter sharedCenter] broadcastEntry];

	// 添付ファイルサーバの起動
	TRC(@"Start attachment server");
	[AttachmentServer sharedServer];

	TRC(@"Complete");
}

// ログ参照クリック時
- (void) openLog:(id)sender{
	Config*	config	= [Config sharedConfig];
	// ログファイルのフルパスを取得する
	NSString *filePath = [config.standardLogFile stringByExpandingTildeInPath];
	// デフォルトのアプリでログを開く
	[[NSWorkspace sharedWorkspace] openFile : filePath];
}

// アプリ終了前確認
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
	// 表示されている受信ウィンドウがあれば終了確認
	NSEnumerator*	e = [[NSApp orderedWindows] objectEnumerator];
	NSWindow*		win;
	while ((win = (NSWindow*)[e nextObject])) {
		if ([win isVisible] && [[win delegate] isKindOfClass:[ReceiveControl class]]) {
			int ret = NSRunCriticalAlertPanel(
								NSLocalizedString(@"ShutDown.Confirm1.Title", nil),
								NSLocalizedString(@"ShutDown.Confirm1.Msg", nil),
								NSLocalizedString(@"ShutDown.Confirm1.OK", nil),
								NSLocalizedString(@"ShutDown.Confirm1.Cancel", nil),
								nil);
			if (ret == NSAlertAlternateReturn) {
				[win makeKeyAndOrderFront:self];
				// 終了キャンセル
				return NSTerminateCancel;
			}
			break;
		}
	}
	// ノンポップアップの未読メッセージがあれば終了確認
	[receiveQueueLock lock];
	if ([receiveQueue count] > 0) {
		int ret = NSRunCriticalAlertPanel(
								NSLocalizedString(@"ShutDown.Confirm2.Title", nil),
								NSLocalizedString(@"ShutDown.Confirm2.Msg", nil),
								NSLocalizedString(@"ShutDown.Confirm2.OK", nil),
								NSLocalizedString(@"ShutDown.Confirm2.Other", nil),
								NSLocalizedString(@"ShutDown.Confirm2.Cancel", nil));
		if (ret == NSAlertOtherReturn) {
			[receiveQueueLock unlock];
			// 終了キャンセル
			return NSTerminateCancel;
		} else if (ret == NSAlertAlternateReturn) {
			[receiveQueueLock unlock];
			[self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
			// 終了キャンセル
			return NSTerminateCancel;
		}
	}
	[receiveQueueLock unlock];
	// 終了
	return NSTerminateNow;
}

// アプリ終了時処理
- (void)applicationWillTerminate:(NSNotification*)aNotification {
	// EXITパケットのブロードキャスト
	[[MessageCenter sharedCenter] broadcastExit];
	// 添付ファイルサーバの終了
	[[AttachmentServer sharedServer] shutdownServer];

	// ステータスバー消去
	if ([Config sharedConfig].useStatusBar && (statusBarItem != nil)) {
		// [self removeStatusBar]を呼ぶと落ちる（なぜ？）
		[[NSStatusBar systemStatusBar] removeStatusItem:statusBarItem];
	}

	// 初期設定の保存
	[[Config sharedConfig] save];

}

// アプリアクティベート
- (void)applicationDidBecomeActive:(NSNotification*)aNotification {
	// 初回だけは無視（起動時のアクティベートがあるので）
	activatedFlag = (activatedFlag == -1) ? NO : YES;
}

// Dockファイルドロップ時
- (BOOL)application:(NSApplication*)theApplication openFile:(NSString*)fileName {
	DBG(@"drop file=%@", fileName);
	if (lastDockDraggedDate && lastDockDraggedWindow) {
		if ([lastDockDraggedDate timeIntervalSinceNow] > -0.5) {
			[lastDockDraggedWindow appendAttachmentByPath:fileName];
		} else {
			[lastDockDraggedDate release];
			lastDockDraggedDate		= nil;
			lastDockDraggedWindow	= nil;
		}
	}
	if (!lastDockDraggedDate) {
		lastDockDraggedWindow = [[SendControl alloc] initWithSendMessage:nil recvMessage:nil];
		[lastDockDraggedWindow appendAttachmentByPath:fileName];
		lastDockDraggedDate = [[NSDate alloc] init];
	}
	return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
	if (item == showNonPopupMenuItem) {
		if ([Config sharedConfig].nonPopup) {
			return ([receiveQueue count] > 0);
		}
		return NO;
	}
	return YES;
}

- (IBAction)showNonPopupMessage:(id)sender {
	[self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
}

// Dockクリック時
- (BOOL)applicationShouldHandleReopen:(NSApplication*)theApplication hasVisibleWindows:(BOOL)flag {
	int 		i;
	BOOL		b;
	BOOL		noWin = YES;
	Config*		config = [Config sharedConfig];
	NSArray*	wins;
	// ノンポップアップのキューにメッセージがあれば表示
	[receiveQueueLock lock];
	b = ([receiveQueue count] > 0);
	for (i = 0; i < [receiveQueue count]; i++) {
		[[receiveQueue objectAtIndex:i] showWindow];
	}
	[receiveQueue removeAllObjects];
	// アイコントグルアニメーションストップ
	if (b && iconToggleTimer) {
		[iconToggleTimer invalidate];
		iconToggleTimer = nil;
		[NSApp setApplicationIconImage:((config.inAbsence) ? iconAbsence : iconNormal)];
		[statusBarItem setImage:((config.inAbsence) ? iconSmallAbsence : iconSmallNormal)];
	}
	[receiveQueueLock unlock];
    statusBarItem.title = @"";
	// 新規送信ウィンドウのオープン
    
//    //DBG(@"#window = %d", [[NSApp windows] count]);
//	wins = [NSApp windows];
//	for (i = 0; i < [wins count]; i++) {
//		NSWindow* win = [wins objectAtIndex:i];
////		[win orderFront:self];
////		if ([[win delegate] isKindOfClass:[ReceiveControl class]] ||
////			[[win delegate] isKindOfClass:[SendControl class]]) {
//		if ([win isVisible]) {
//			noWin = NO;
//			break;
//		}
//	}
//	if (activatedFlag != -1) {
//		if ((noWin || !activatedFlag) &&
//			!b && config.openNewOnDockClick) {
//			// ・クリック前からアクティブアプリだったか、または表示中のウィンドウが一個もない
//			// ・環境設定で指定されている
//			// ・ノンポップアップ受信でキューイングされた受信ウィンドウがない
//			// のすべてを満たす場合、新規送信ウィンドウを開く
//			[self newMessage:self];
//		}
//	}
//	activatedFlag = YES;
    [self newMessage:self];
	return YES;
}

// アイコン点滅処理（タイマコールバック）
- (void)toggleIcon:(NSTimer*)timer {
	NSImage* img1;
	NSImage* img2;
	iconToggleState = !iconToggleState;


	if ([Config sharedConfig].inAbsence) {
		img1 = (iconToggleState) ? iconAbsence : iconAbsenceReverse;
		img2 = (iconToggleState) ? iconSmallAbsence : iconSmallAbsenceReverse;
	} else {
		img1 = (iconToggleState) ? iconNormal : iconNormalReverse;
		img2 = (iconToggleState) ? iconSmallNormal : iconSmallNormalReverse;
	}

	// ステータスバーアイコン
	if ([Config sharedConfig].useStatusBar) {
		if (statusBarItem == nil) {
			[self initStatusBar];
		}
		[statusBarItem setImage:img2];
	}
    statusBarItem.title = [NSString stringWithFormat:@"%d",[receiveQueue count]];
	// Dockアイコン
	[NSApp setApplicationIconImage:img1];
}

- (void)checkLogConversion:(BOOL)aStdLog path:(NSString*)aPath
{
	Config*			config	= [Config sharedConfig];
	NSString*		name	= aStdLog ? @"StdLog" : @"AltLog";
	LogConverter*	converter;

	TRC(@"Start check %@ logfile", name);

	converter		= [LogConverter converter];
	converter.name	= name;
	converter.path	= [aPath stringByExpandingTildeInPath];

	if (![converter needConversion]) {
		TRC(@"%@ is up to date (UTF-8) -> end", name);
		return;
	}

	// ユーザへの変換確認
	WRN(@"%@ need to convert (SJIS->UTF-8) -> user confirm", name);
	NSString*	s		= [NSString stringWithFormat:@"Log.Conv.%@", name];
	NSString*	logName	= NSLocalizedString(s, nil);
	NSString*	title	= NSLocalizedString(@"Log.Conv.Title", nil);
	NSString*	message	= NSLocalizedString(@"Log.Conv.Message", nil);
	NSString*	ok		= NSLocalizedString(@"Log.Conv.OK", nil);
	NSString*	cancel	= NSLocalizedString(@"Log.Conv.Cancel", nil);

	NSAlert*	alert	= [[NSAlert alloc] init];
	[alert setMessageText:[NSString stringWithFormat:title, logName]];
	[alert setInformativeText:[NSString stringWithFormat:message, logName]];
	[alert addButtonWithTitle:ok];
	[alert addButtonWithTitle:cancel];
	[alert setAlertStyle:NSWarningAlertStyle];
	NSInteger ret = [alert runModal];
	[alert release];
	if (ret == NSAlertFirstButtonReturn) {
		// OKを選んだら変換
		TRC(@"User confirmed %@ conversion", name);

		// 進捗ダイアログ作成
		LogConvertController* dialog = [[LogConvertController alloc] init];
		dialog.filePath	= converter.path;
		converter.delegate	= dialog;
		[dialog showWindow:self];

		// 変換処理
		TRC(@"LogConvert start(%@)", name);
		BOOL result = [converter convertToUTF8:[dialog window]];
		TRC(@"LogConvert result(%@,%s)", name, (result ? "YES" : "NO"));
		[dialog close];
		[dialog release];
		if (result == NO) {
			if ([converter.backupPath length] == 0) {
				// バックアップされていないようであればバックアップ
				[converter backup];
			}
			title	= NSLocalizedString(@"Log.ConvFail.Title", nil);
			message	= NSLocalizedString(@"Log.ConvFail.Message", nil);
			ok		= NSLocalizedString(@"Log.ConvFail.OK", nil);
			alert = [[NSAlert alloc] init];
			alert.alertStyle		= NSCriticalAlertStyle;
			alert.messageText		= title;
			alert.informativeText	= message;
			[alert addButtonWithTitle:ok];
			[alert setAlertStyle:NSCriticalAlertStyle];
			[alert runModal];
		}
	} else if (ret == NSAlertSecondButtonReturn) {
		// キャンセルを選んだ場合はログファイルをバックアップ
		ERR(@"User denied %@ conversion. -> backup", name);
		[converter backup];
	}

	if ([converter.backupPath length] > 0) {
		title	= NSLocalizedString(@"Log.Backup.Title", nil);
		ok		= NSLocalizedString(@"Log.Backup.OK", nil);
		alert = [[NSAlert alloc] init];
		alert.alertStyle		= NSInformationalAlertStyle;
		alert.messageText		= title;
		alert.informativeText	= converter.backupPath;
		[alert addButtonWithTitle:ok];
		[alert setAlertStyle:NSInformationalAlertStyle];
		[alert runModal];
	}
}

@end
