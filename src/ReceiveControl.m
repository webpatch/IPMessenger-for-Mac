/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: ReceiveControl.m
 *	Module		: 受信メッセージウィンドウコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import "ReceiveControl.h"
#import "Config.h"
#import "UserInfo.h"
#import "LogManager.h"
#import "MessageCenter.h"
#import "WindowManager.h"
#import "RecvMessage.h"
#import "SendControl.h"
#import "AttachmentFile.h"
#import "Attachment.h"
#import "DebugLog.h"

#include <unistd.h>

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation ReceiveControl

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)initWithRecvMessage:(RecvMessage*)msg {
	Config*		config = [Config sharedConfig];

	self = [super init];

	if (!msg) {
		[self autorelease];
		return nil;
	}

	if (![NSBundle loadNibNamed:@"ReceiveWindow.nib" owner:self]) {
		[self autorelease];
		return nil;
	}

	// ログ出力
	if (config.standardLogEnabled) {
		if (![msg locked] || !config.logChainedWhenOpen) {
			[[LogManager standardLog] writeRecvLog:msg];
			[msg setNeedLog:NO];
		}
	}

	// 表示内容の設定
	[dateLabel setObjectValue:msg.receiveDate];
	[userNameLabel setStringValue:[[msg fromUser] summaryString]];
	[messageArea setString:[msg appendix]];
	if ([msg multicast]) {
		[infoBox setTitle:NSLocalizedString(@"RecvDlg.BoxTitleMulti", nil)];
	} else if ([msg broadcast]) {
		[infoBox setTitle:NSLocalizedString(@"RecvDlg.BoxTitleBroad", nil)];
	} else if ([msg absence]) {
		[infoBox setTitle:NSLocalizedString(@"RecvDlg.BoxTitleAbsence", nil)];
	}
	if (![msg sealed]) {
		[sealButton removeFromSuperview];
		[window makeFirstResponder:messageArea];
	} else {
		[replyButton setEnabled:NO];
		[quotCheck setEnabled:NO];
		[window makeFirstResponder:sealButton];
	}
	if ([msg locked]) {
		[sealButton setTitle:NSLocalizedString(@"RecvDlg.LockBtnStr", nil)];
	}

	// クリッカブルURL設定
	if (config.useClickableURL) {
		NSMutableAttributedString*	attrStr;
		NSScanner*					scanner;
		NSCharacterSet*				charSet;
		NSArray*					schemes;
		attrStr	= [messageArea textStorage];
		scanner	= [NSScanner scannerWithString:[msg appendix]];
		charSet	= [NSCharacterSet characterSetWithCharactersInString:NSLocalizedString(@"RecvDlg.URL.Delimiter", nil)];
		schemes = [NSArray arrayWithObjects:@"http://", @"https://", @"ftp://", @"file://", @"rtsp://", @"afp://", @"mailto:", nil];
		while (![scanner isAtEnd]) {
			NSString*	sentence;
			NSRange		range;
			unsigned	i;
			if (![scanner scanUpToCharactersFromSet:charSet intoString:&sentence]) {
				continue;
			}
			for (i = 0; i < [schemes count]; i++) {
				range = [sentence rangeOfString:[schemes objectAtIndex:i]];
				if (range.location != NSNotFound) {
					if (range.location > 0) {
						sentence	= [sentence substringFromIndex:range.location];
					}
					range.length	= [sentence length];
					range.location	= [scanner scanLocation] - [sentence length];
					[attrStr addAttribute:NSLinkAttributeName value:sentence range:range];
					[attrStr addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:range];
					[attrStr addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:1] range:range];
					break;
				}
			}
			if (i < [schemes count]) {
				continue;
			}
			range = [sentence rangeOfString:@"://"];
			if (range.location != NSNotFound) {
				range.location	= [scanner scanLocation] - [sentence length];
				range.length	= [sentence length];
				[attrStr addAttribute:NSLinkAttributeName value:sentence range:range];
				[attrStr addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:range];
				[attrStr addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:1] range:range];
				continue;
			}
		}
	}

	recvMsg = [msg retain];
	[[WindowManager sharedManager] setReceiveWindow:self forKey:recvMsg];

	if (![recvMsg sealed]) {
		// 重要ログボタンの有効／無効
		if (config.alternateLogEnabled) {
			[altLogButton setEnabled:config.alternateLogEnabled];
		} else {
			[altLogButton setHidden:YES];
		}

		// 添付ボタンの有効／無効
		if ([[recvMsg attachments] count] > 0) {
			[attachButton setEnabled:YES];
		}
	}

	[self setAttachHeader];
	[attachTable reloadData];
	[attachTable selectAll:self];

	downloader = nil;
	pleaseCloseMe = NO;
	attachSheetRefreshTimer = nil;

	return self;
}

// 解放処理
- (void)dealloc {
	[recvMsg release];
	[downloader release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * ウィンドウ表示
 *----------------------------------------------------------------------------*/

- (void)showWindow {
	NSWindow* orgKeyWin = [NSApp keyWindow];
	if (orgKeyWin) {
		if ([[orgKeyWin delegate] isKindOfClass:[SendControl class]]) {
			[window orderFront:self];
			[orgKeyWin orderFront:self];
		} else {
			[window makeKeyAndOrderFront:self];
		}
	} else {
		[window makeKeyAndOrderFront:self];
	}
	if (([[recvMsg attachments] count] > 0) && ![recvMsg sealed]) {
		[attachDrawer open];
	}
}

/*----------------------------------------------------------------------------*
 * ボタン
 *----------------------------------------------------------------------------*/

- (IBAction)buttonPressed:(id)sender {
	if (sender == attachSaveButton) {
		attachSaveButton.enabled = NO;
		NSOpenPanel* op = [NSOpenPanel openPanel];
		op.canChooseFiles = NO;
		op.canChooseDirectories = YES;
		op.prompt = NSLocalizedString(@"RecvDlg.Attach.SelectBtn", nil);
		[op beginSheetModalForWindow:window completionHandler:^(NSInteger result) {
			if (result == NSOKButton) {
				NSFileManager*	fileManager	= [NSFileManager defaultManager];
				NSURL*			directory	= op.directoryURL;
				NSIndexSet*		indexes		= [attachTable selectedRowIndexes];
				[downloader release];
				downloader = [[AttachmentClient alloc] initWithRecvMessage:recvMsg saveTo:directory.path];
				[recvMsg.attachments enumerateObjectsAtIndexes:indexes options:NSEnumerationConcurrent usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
					Attachment* attach = obj;
					NSString* path;
					path = [directory.path stringByAppendingPathComponent:[[attach file] name]];
					// ファイル存在チェック
					if ([fileManager fileExistsAtPath:path]) {
						// 上書き確認
						int result;
						WRN(@"file exists(%@)", path);
						if ([[attach file] isDirectory]) {
							result = NSRunAlertPanel(NSLocalizedString(@"RecvDlg.AttachDirOverwrite.Title", nil),
													 NSLocalizedString(@"RecvDlg.AttachDirOverwrite.Msg", nil),
													 NSLocalizedString(@"RecvDlg.AttachDirOverwrite.OK", nil),
													 NSLocalizedString(@"RecvDlg.AttachDirOverwrite.Cancel", nil),
													 nil,
													 [[attach file] name]);
						} else {
							result = NSRunAlertPanel(NSLocalizedString(@"RecvDlg.AttachFileOverwrite.Title", nil),
													 NSLocalizedString(@"RecvDlg.AttachFileOverwrite.Msg", nil),
													 NSLocalizedString(@"RecvDlg.AttachFileOverwrite.OK", nil),
													 NSLocalizedString(@"RecvDlg.AttachFileOverwrite.Cancel", nil),
													 nil,
													 [[attach file] name]);
						}
						switch (result) {
							case NSAlertDefaultReturn:
								DBG(@"overwrite ok.");
								break;
							case NSAlertAlternateReturn:
								DBG(@"overwrite canceled.");
								[attachTable deselectRow:idx];	// 選択解除
								return;
							default:
								ERR(@"inernal error.");
								break;
						}
					}
					[downloader addTarget:attach];
				}];
				if ([downloader numberOfTargets] == 0) {
					WRN(@"downloader has no targets");
					[downloader release];
					downloader = nil;
					return;
				}
				// ダウンロード準備（UI）
				[attachSaveButton setEnabled:NO];
				[attachTable setEnabled:NO];
				[attachSheetProgress setIndeterminate:NO];
				[attachSheetProgress setMaxValue:[downloader totalSize]];
				[attachSheetProgress setDoubleValue:0];
				// シート表示
				[NSApp beginSheet:attachSheet
				   modalForWindow:window
					modalDelegate:self
				   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
					  contextInfo:nil];
				// ダウンロード（スレッド）開始
				attachSheetRefreshTitle			= NO;
				attachSheetRefreshFileName		= NO;
				attachSheetRefreshPercentage	= NO;
				attachSheetRefreshFileNum		= NO;
				attachSheetRefreshDirNum		= NO;
				attachSheetRefreshSize			= NO;
				[downloader startDownload:self];
				attachSheetRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
																		   target:self
																		 selector:@selector(downloadSheetRefresh:)
																		 userInfo:nil
																		  repeats:YES];
			} else {
				[attachSaveButton setEnabled:([attachTable numberOfSelectedRows] > 0)];
			}
		}];
	} else if (sender == attachSheetCancelButton) {
		[downloader stopDownload];
	} else {
		DBG(@"Unknown button pressed(%@)", sender);
	}
}

- (void)attachTableDoubleClicked:(id)sender {
	if (sender == attachTable) {
		[self buttonPressed:attachSaveButton];
	}
}

// シート終了処理
- (void)sheetDidEnd:(NSWindow*)sheet returnCode:(int)code contextInfo:(void*)info {
	if (sheet == attachSheet) {
		[attachSheetRefreshTimer invalidate];
		attachSheetRefreshTimer = nil;
		[recvMsg removeDownloadedAttachments];
		[sheet orderOut:self];
		[attachSaveButton setEnabled:([attachTable numberOfSelectedRows] > 0)];
		[attachTable reloadData];
		[self setAttachHeader];
		[attachTable setEnabled:YES];
		if ([[recvMsg attachments] count] <= 0) {
//			[attachDrawer performSelectorOnMainThread:@selector(close:) withObject:self waitUntilDone:YES];
			[attachDrawer close];
			[attachButton setEnabled:NO];
		}
		[downloader autorelease];
		downloader = nil;
	}
	else if (info == recvMsg) {
		[sheet orderOut:self];
		if (code == NSOKButton) {
			pleaseCloseMe = YES;
			[window performClose:self];
		}
	}
}

/*----------------------------------------------------------------------------*
 * 返信処理
 *----------------------------------------------------------------------------*/

- (BOOL)validateMenuItem:(NSMenuItem*)item {
	// 封書開封前はメニューとキーボードショートカットで返信できてしまわないようにする
	// （メニューアイテムの判定方法が暫定）
	if ([[item keyEquivalent] isEqualToString:@"r"] && ([item keyEquivalentModifierMask] & NSCommandKeyMask)) {
		return [replyButton isEnabled];
	}
	return YES;
}

// 返信ボタン押下時処理
- (IBAction)replyMessage:(id)sender {
	Config*		config	= [Config sharedConfig];
	NSString*	quotMsg	= nil;
	id			sendCtl	= [[WindowManager sharedManager] replyWindowForKey:recvMsg];
	if (sendCtl) {
		[[sendCtl window] makeKeyAndOrderFront:self];
		return;
	}
	if ([quotCheck state]) {
		NSString* quote = config.quoteString;

		// 選択範囲があれば選択範囲を引用、なければ全文引用
		NSRange	range = [messageArea selectedRange];
		if (range.length <= 0) {
			quotMsg = [messageArea string];
		} else {
			quotMsg = [[messageArea string] substringWithRange:range];
		}
		if (([quotMsg length] > 0) && ([quote length] > 0)) {
			// 引用文字を入れる
			NSArray*			array;
			NSMutableString*	strBuf;
			int					lines;
			int					iCount;
			array	= [quotMsg componentsSeparatedByString:@"\n"];
			lines	= [array count];
			strBuf	= [NSMutableString stringWithCapacity:
							[quotMsg length] + ([quote length] + 1) * lines];
			for (iCount = 0; iCount < lines; iCount++) {
				[strBuf appendString:quote];
				[strBuf appendString:[array objectAtIndex:iCount]];
				[strBuf appendString:@"\n"];
			}
			quotMsg = strBuf;
		}
	}
	// 送信ダイアログ作成
	sendCtl = [[SendControl alloc] initWithSendMessage:quotMsg recvMessage:recvMsg];
}

/*----------------------------------------------------------------------------*
 * 封書関連処理
 *----------------------------------------------------------------------------*/

// 封書ボタン押下時処理
- (IBAction)openSeal:(id)sender {
	if ([recvMsg locked]) {
		// 鍵付きの場合
		// フィールド／ラベルをクリア
		[pwdSheetField setStringValue: @""];
		[pwdSheetErrorLabel setStringValue: @""];
		// シート表示
		[NSApp beginSheet:pwdSheet
		   modalForWindow:window
			modalDelegate:self
		   didEndSelector:@selector(pwdSheetDidEnd:returnCode:contextInfo:)
			  contextInfo:nil];
	} else {
		// 封書消去
		[sender removeFromSuperview];
		[replyButton setEnabled:YES];
		[quotCheck setEnabled:YES];
		[altLogButton setEnabled:[Config sharedConfig].alternateLogEnabled];
		if ([[recvMsg attachments] count] > 0) {
			[attachButton setEnabled:YES];
			[attachDrawer open];
		}

		// 封書開封通知送信
		[[MessageCenter sharedCenter] sendOpenSealMessage:recvMsg];
	}
}

// パスワードシート終了処理
- (void)pwdSheetDidEnd:(NSWindow*)sheet returnCode:(int)code contextInfo:(void*)info {
	[pwdSheet orderOut:self];
}

// パスワード入力シートOKボタン押下時処理
- (IBAction)okPwdSheet:(id)sender {
	NSString*	password	= [Config sharedConfig].password;
	NSString*	input		= [pwdSheetField stringValue];

	// パスワードチェック
	if (password) {
		if ([password length] > 0) {
			if ([input length] <= 0) {
				[pwdSheetErrorLabel setStringValue:NSLocalizedString(@"RecvDlg.PwdChk.NoPwd", nil)];
				return;
			}
			if (![password isEqualToString:[NSString stringWithCString:crypt([input UTF8String], "IP") encoding:NSUTF8StringEncoding]] &&
				![password isEqualToString:input]) {
				// 平文とも比較するのはv0.4までとの互換性のため
				[pwdSheetErrorLabel setStringValue:NSLocalizedString(@"RecvDlg.PwdChk.PwdErr", nil)];
				return;
			}
		}
	}

	// 封書消去
	[sealButton removeFromSuperview];
	[replyButton setEnabled:YES];
	[quotCheck setEnabled:YES];
	[altLogButton setEnabled:[Config sharedConfig].alternateLogEnabled];
	if ([[recvMsg attachments] count] > 0) {
		[attachButton setEnabled:YES];
		[attachDrawer open];
	}

	// ログ出力
	if ([recvMsg needLog]) {
		[[LogManager standardLog] writeRecvLog:recvMsg];
		[recvMsg setNeedLog:NO];
	}

	// 封書開封通知送信
	[[MessageCenter sharedCenter] sendOpenSealMessage:recvMsg];

	[NSApp endSheet:pwdSheet returnCode:NSOKButton];
}

// パスワード入力シートキャンセルボタン押下時処理
- (IBAction)cancelPwdSheet:(id)sender {
	[NSApp endSheet:pwdSheet returnCode:NSCancelButton];
}

/*----------------------------------------------------------------------------*
 * 添付ファイル
 *----------------------------------------------------------------------------*/

- (void)downloadSheetRefresh:(NSTimer*)timer {
	if (attachSheetRefreshTitle) {
		unsigned num	= [downloader numberOfTargets];
		unsigned index	= [downloader indexOfTarget] + 1;
		NSString* title = [NSString stringWithFormat:NSLocalizedString(@"RecvDlg.AttachSheet.Title", nil), index, num];
		[attachSheetTitleLabel setStringValue:title];
		attachSheetRefreshTitle = NO;
	}
	if (attachSheetRefreshFileName) {
		[attachSheetFileNameLabel setStringValue:[downloader currentFile]];
		attachSheetRefreshFileName = NO;
	}
	if (attachSheetRefreshFileNum) {
		[attachSheetFileNumLabel setObjectValue:[NSNumber numberWithUnsignedInt:[downloader numberOfFile]]];
		attachSheetRefreshFileNum = NO;
	}
	if (attachSheetRefreshDirNum) {
		[attachSheetDirNumLabel setObjectValue:[NSNumber numberWithUnsignedInt:[downloader numberOfDirectory]]];
		attachSheetRefreshDirNum = NO;
	}
	if (attachSheetRefreshPercentage) {
		[attachSheetPercentageLabel setStringValue:[NSString stringWithFormat:@"%d %%", [downloader percentage]]];
		attachSheetRefreshPercentage = NO;
	}
	if (attachSheetRefreshSize) {
		double		downSize	= [downloader downloadSize];
		double		totalSize	= [downloader totalSize];
		NSString*	str			= nil;
		float		bps;
		if (totalSize < 1024) {
			str = [NSString stringWithFormat:@"%d / %d Bytes", (int)downSize, (int)totalSize];
		}
		if (!str) {
			downSize /= 1024.0;
			totalSize /= 1024.0;
			if (totalSize < 1024) {
				str = [NSString stringWithFormat:@"%.1f / %.1f KBytes", downSize, totalSize];
			}
		}
		if (!str) {
			downSize /= 1024.0;
			totalSize /= 1024.0;
			if (totalSize < 1024) {
				str = [NSString stringWithFormat:@"%.2f / %.2f MBytes", downSize, totalSize];
			}
		}
		if (!str) {
			downSize /= 1024.0;
			totalSize /= 1024.0;
			str = [NSString stringWithFormat:@"%.2f / %.2f GBytes", downSize, totalSize];
		}
		[attachSheetSizeLabel setStringValue:str];
		bps = ((float)[downloader averageSpeed] / 1024.0f);
		if (bps < 1024) {
			[attachSheetSpeedLabel setStringValue:[NSString stringWithFormat:@"%0.1f KBytes/sec", bps]];
		} else {
			bps /= 1024.0;
			[attachSheetSpeedLabel setStringValue:[NSString stringWithFormat:@"%0.2f MBytes/sec", bps]];
		}
		attachSheetRefreshSize = NO;
	}
}

- (void)downloadWillStart {
	[attachSheetTitleLabel setStringValue:NSLocalizedString(@"RecvDlg.AttachSheet.Start", nil)];
	[attachSheetFileNameLabel setStringValue:@""];
	attachSheetRefreshTitle			= NO;
	attachSheetRefreshFileName		= NO;
	attachSheetRefreshFileNum		= YES;
	attachSheetRefreshDirNum		= YES;
	attachSheetRefreshPercentage	= YES;
	attachSheetRefreshSize			= YES;
	[self downloadSheetRefresh:nil];
}

- (void)downloadDidFinished:(DownloadResult)result {
	[attachSheetTitleLabel setStringValue:NSLocalizedString(@"RecvDlg.AttachSheet.Finish", nil)];
	[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
	[NSApp endSheet:attachSheet returnCode:NSOKButton];
	if ((result != DL_SUCCESS) && (result != DL_STOP)) {
		NSString* msg = nil;
		switch (result) {
		case DL_TIMEOUT:				// 通信タイムアウト
			msg = NSLocalizedString(@"RecvDlg.DownloadError.TimeOut", nil);
			break;
		case DL_CONNECT_ERROR:			// 接続セラー
			msg = NSLocalizedString(@"RecvDlg.DownloadError.Connect", nil);
			break;
		case DL_DISCONNECTED:
			msg = NSLocalizedString(@"RecvDlg.DownloadError.Disconnected", nil);
			break;
		case DL_SOCKET_ERROR:			// ソケットエラー
			msg = NSLocalizedString(@"RecvDlg.DownloadError.Socket", nil);
			break;
		case DL_COMMUNICATION_ERROR:	// 送受信エラー
			msg = NSLocalizedString(@"RecvDlg.DownloadError.Communication", nil);
			break;
		case DL_FILE_OPEN_ERROR:		// ファイルオープンエラー
			msg = NSLocalizedString(@"RecvDlg.DownloadError.FileOpen", nil);
			break;
		case DL_INVALID_DATA:			// 異常データ受信
			msg = NSLocalizedString(@"RecvDlg.DownloadError.InvalidData", nil);
			break;
		case DL_INTERNAL_ERROR:			// 内部エラー
			msg = NSLocalizedString(@"RecvDlg.DownloadError.Internal", nil);
			break;
		case DL_SIZE_NOT_ENOUGH:		// ファイルサイズ以上
			msg = NSLocalizedString(@"RecvDlg.DownloadError.FileSize", nil);
			break;
		case DL_OTHER_ERROR:			// その他エラー
		default:
			msg = NSLocalizedString(@"RecvDlg.DownloadError.OtherError", nil);
			break;
		}
		NSBeginCriticalAlertSheet(	NSLocalizedString(@"RecvDlg.DownloadError.Title", nil),
									NSLocalizedString(@"RecvDlg.DownloadError.OK", nil),
									nil, nil, window, nil, nil, nil, nil, msg, result);
	}
}

- (void)downloadFileChanged {
	attachSheetRefreshFileName = YES;
}

- (void)downloadNumberOfFileChanged {
	attachSheetRefreshFileNum = YES;
}

- (void)downloadNumberOfDirectoryChanged {
	attachSheetRefreshDirNum = YES;
}

- (void)downloadIndexOfTargetChanged {
	attachSheetRefreshTitle	= YES;
}

- (void)downloadTotalSizeChanged {
	[attachSheetProgress setMaxValue:[downloader totalSize]];
	attachSheetRefreshSize = YES;
}

- (void)downloadDownloadedSizeChanged {
	[attachSheetProgress setDoubleValue:[downloader downloadSize]];
	attachSheetRefreshSize = YES;
}

- (void)downloadPercentageChanged {
	attachSheetRefreshPercentage = YES;
}

/*----------------------------------------------------------------------------*
 * NSTableDataSourceメソッド
 *----------------------------------------------------------------------------*/

- (int)numberOfRowsInTableView:(NSTableView*)aTableView {
	if (aTableView == attachTable) {
		return [[recvMsg attachments] count];
	} else {
		ERR(@"Unknown TableView(%@)", aTableView);
	}
	return 0;
}

- (id)tableView:(NSTableView*)aTableView
		objectValueForTableColumn:(NSTableColumn*)aTableColumn
		row:(int)rowIndex {
	if (aTableView == attachTable) {
		Attachment*					attach;
		NSMutableAttributedString*	cellValue;
		NSFileWrapper*				fileWrapper;
		NSTextAttachment*			textAttachment;
		if (rowIndex >= [[recvMsg attachments] count]) {
			ERR(@"invalid index(row=%d)", rowIndex);
			return nil;
		}
		attach = [[recvMsg attachments] objectAtIndex:rowIndex];
		if (!attach) {
			ERR(@"no attachments(row=%d)", rowIndex);
			return nil;
		}
		fileWrapper		= [[NSFileWrapper alloc] initRegularFileWithContents:nil];
		textAttachment	= [[NSTextAttachment alloc] initWithFileWrapper:fileWrapper];
		[(NSCell*)[textAttachment attachmentCell] setImage:attach.icon];
		cellValue		= [[[NSMutableAttributedString alloc] initWithString:[[attach file] name]] autorelease];
		[cellValue replaceCharactersInRange:NSMakeRange(0, 0)
					   withAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
		[cellValue addAttribute:NSBaselineOffsetAttributeName
						  value:[NSNumber numberWithFloat:-3.0]
						  range:NSMakeRange(0, 1)];
		[textAttachment release];
		[fileWrapper release];
		return cellValue;
	} else {
		ERR(@"Unknown TableView(%@)", aTableView);
	}
	return nil;
}

// ユーザリストの選択変更
- (void)tableViewSelectionDidChange:(NSNotification*)aNotification {
	NSTableView* table = [aNotification object];
	if (table == attachTable) {
		float			size	= 0;
		NSUInteger		index;
		NSIndexSet*		selects = [attachTable selectedRowIndexes];
		Attachment*		attach	= nil;

		index = [selects firstIndex];
		while (index != NSNotFound) {
			attach	= [[recvMsg attachments] objectAtIndex:index];
			size	+= (float)[attach file].size / 1024;
			index	= [selects indexGreaterThanIndex:index];
		}
		[attachSaveButton setEnabled:([selects count] > 0)];
	} else {
		ERR(@"Unknown TableView(%@)", table);
	}
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

- (NSWindow*)window {
	return window;
}

// 一番奥のウィンドウを手前に移動
- (IBAction)backWindowToFront:(id)sender {
	NSArray*	wins	= [NSApp orderedWindows];
	int			i;
	for (i = [wins count] - 1; i >= 0; i--) {
		NSWindow* win = [wins objectAtIndex:i];
		if ([win isVisible] && [[win delegate] isKindOfClass:[ReceiveControl class]]) {
			[win makeKeyAndOrderFront:self];
			break;
		}
	}
}

// メッセージ部フォントパネル表示
- (void)showReceiveMessageFontPanel:(id)sender {
	[[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

// メッセージ部フォント保存
- (void)saveReceiveMessageFont:(id)sender {
	[Config sharedConfig].receiveMessageFont = [messageArea font];
}

// メッセージ部フォントを標準に戻す
- (void)resetReceiveMessageFont:(id)sender {
	[messageArea setFont:[Config sharedConfig].defaultReceiveMessageFont];
}

// 重要ログボタン押下時処理
- (IBAction)writeAlternateLog:(id)sender
{
	if ([Config sharedConfig].logWithSelectedRange) {
		[[LogManager alternateLog] writeRecvLog:recvMsg withRange:[messageArea selectedRange]];
	} else {
		[[LogManager alternateLog] writeRecvLog:recvMsg];
	}
	[altLogButton setEnabled:NO];
}

// Nibファイルロード時処理
- (void)awakeFromNib {
	Config* config	= [Config sharedConfig];
	NSSize	size	= config.receiveWindowSize;
	NSRect	frame	= [window frame];

	// ウィンドウ位置、サイズ決定
	int sw	= [[NSScreen mainScreen] visibleFrame].size.width;
	int sh	= [[NSScreen mainScreen] visibleFrame].size.height;
	int ww	= [window frame].size.width;
	int wh	= [window frame].size.height;
	frame.origin.x = (sw - ww) / 2 + (rand() % (sw / 4)) - sw / 8;
	frame.origin.y = (sh - wh) / 2 + (rand() % (sh / 4)) - sh / 8;
	if ((size.width != 0) || (size.height != 0)) {
		frame.size.width	= size.width;
		frame.size.height	= size.height;
	}
	[window setFrame:frame display:NO];

	// 引用チェックをデフォルト判定
	if (config.quoteCheckDefault) {
		[quotCheck setState:YES];
	}

	// 添付リストの行設定
	[attachTable setRowHeight:16.0];

	// 添付テーブルダブルクリック時処理
	[attachTable setDoubleAction:@selector(attachTableDoubleClicked:)];

//	[attachSheetProgress setUsesThreadedAnimation:YES];
}

// ウィンドウリサイズ時処理
- (void)windowDidResize:(NSNotification *)notification
{
	// ウィンドウサイズを保存
	[Config sharedConfig].receiveWindowSize = [window frame].size;
}

// ウィンドウクローズ判定処理
- (BOOL)windowShouldClose:(id)sender {
	if (!pleaseCloseMe && ([[recvMsg attachments] count] > 0)) {
		// 添付ファイルが残っているがクローズするか確認
		NSBeginAlertSheet(	NSLocalizedString(@"RecvDlg.CloseWithAttach.Title", nil),
							NSLocalizedString(@"RecvDlg.CloseWithAttach.OK", nil),
							NSLocalizedString(@"RecvDlg.CloseWithAttach.Cancel", nil),
							nil,
							window,
							self,
							@selector(sheetDidEnd:returnCode:contextInfo:),
							nil,
							recvMsg,
							NSLocalizedString(@"RecvDlg.CloseWithAttach.Msg", nil));
		[attachDrawer open];
		return NO;
	}
	if (!pleaseCloseMe && ![replyButton isEnabled]) {
		// 未開封だがクローズするか確認
		NSBeginAlertSheet(	NSLocalizedString(@"RecvDlg.CloseWithSeal.Title", nil),
							NSLocalizedString(@"RecvDlg.CloseWithSeal.OK", nil),
							NSLocalizedString(@"RecvDlg.CloseWithSeal.Cancel", nil),
							nil,
							window,
							self,
							@selector(sheetDidEnd:returnCode:contextInfo:),
							nil,
							recvMsg,
							NSLocalizedString(@"RecvDlg.CloseWithSeal.Msg", nil));
		return NO;
	}

	return YES;
}

// ウィンドウクローズ時処理
- (void)windowWillClose:(NSNotification*)aNotification {
	if ([[recvMsg attachments] count] > 0) {
		// 添付ファイルが残っている場合破棄通知
		[[MessageCenter sharedCenter] sendReleaseAttachmentMessage:recvMsg];
	}
	[[WindowManager sharedManager] removeReceiveWindowForKey:recvMsg];
// なぜか解放されないので手動で
[attachDrawer release];
	[self release];
}

- (void)setAttachHeader {
	NSString*		format	= NSLocalizedString(@"RecvDlg.Attach.Header", nil);
	NSString*		title	= [NSString stringWithFormat:format, [[recvMsg attachments] count]];
	[[[attachTable tableColumnWithIdentifier:@"Attachment"] headerCell] setStringValue:title];
}

@end
