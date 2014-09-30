/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: PrefControl.m
 *	Module		: 環境設定パネルコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import "PrefControl.h"
#import "AppControl.h"
#import "Config.h"
#import "RefuseInfo.h"
#import "MessageCenter.h"
#import "UserManager.h"
#import "LogManager.h"
#import "DebugLog.h"

#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define	_BETA_MODE	(0)				// betaバージョン以外では無効(0)にすること

#define EVERY_DAY	(60 * 60 * 24)
#define EVERY_WEEK	(EVERY_DAY * 7)
#define EVERY_MONTH	(EVERY_DAY * 30)

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation PrefControl

/*----------------------------------------------------------------------------*
 * 最新状態に更新
 *----------------------------------------------------------------------------*/

- (void)update {
	Config*		config = [Config sharedConfig];
	NSString*	work;

	// 全般タブ
	[baseUserNameField			setStringValue:	config.userName];
	[baseGroupNameField 		setStringValue:	config.groupName];
	[receiveStatusBarCheckBox	setState:		config.useStatusBar];

	// 送信タブ
	[sendQuotField				setStringValue:	config.quoteString];
	[sendSingleClickCheck		setState:		config.openNewOnDockClick];
	[sendDefaultSealCheck		setState:		config.sealCheckDefault];
	[sendHideWhenReplyCheck		setState:		config.hideReceiveWindowOnReply];
	[sendOpenNotifyCheck		setState:		config.noticeSealOpened];
	[sendMultipleUserCheck		setState:		config.allowSendingToMultiUser];
	// 受信タブ
	work = config.receiveSoundName;
	if (work && ([work length] > 0)) {
		[receiveSoundPopup selectItemWithTitle:(work)];
	} else {
		[receiveSoundPopup selectItemAtIndex:0];
	}
	[receiveDefaultQuotCheck	setState:config.quoteCheckDefault];
	[receiveNonPopupCheck		setState:config.nonPopup];
	[receiveNonPopupModeMatrix	setEnabled:config.nonPopup];
	[receiveNonPopupBoundMatrix setEnabled:config.nonPopup];
	[receiveNonPopupBoundMatrix	selectCellWithTag:config.iconBoundModeInNonPopup];
	if (config.nonPopupWhenAbsence) {
		[receiveNonPopupModeMatrix selectCellAtRow:1 column:0];
	}
	[receiveClickableURLCheck	setState:config.useClickableURL];

	// ネットワークタブ
	[netPortNoField				setIntegerValue:config.portNo];
	[netDialupCheck				setState:		config.dialup];

	// ログタブ
	[logStdEnableCheck			setState:		config.standardLogEnabled];
	[logStdWhenOpenChainCheck	setState:		config.logChainedWhenOpen];
	[logStdWhenOpenChainCheck	setEnabled:		config.standardLogEnabled];
	[logStdPathField			setStringValue:	config.standardLogFile];
	[logStdPathField			setEnabled:		config.standardLogEnabled];
	[logStdPathRefButton		setEnabled:		config.standardLogEnabled];
	[logAltEnableCheck			setState:		config.alternateLogEnabled];
	[logAltSelectionCheck		setState:		config.logWithSelectedRange];
	[logAltSelectionCheck		setEnabled:		config.alternateLogEnabled];
	[logAltPathField			setStringValue:	config.alternateLogFile];
	[logAltPathField			setEnabled:		config.alternateLogEnabled];
	[logAltPathRefButton		setEnabled:		config.alternateLogEnabled];

#if _BETA_MODE
	// 強制的にソフトウェアアップデートを行うように設定する
	config.updateAutomaticCheck	= YES;
	config.updateCheckInterval		= 60 * 60 * 12;
#endif

	// アップデートタブ
	BOOL			autoCheck	= config.updateAutomaticCheck;
	NSTimeInterval	interval	= config.updateCheckInterval;
	[updateCheckAutoCheck setState:autoCheck];
	[updateTypeMatrix setEnabled:autoCheck];
	if (interval == EVERY_MONTH) {
		[updateTypeMatrix selectCellWithTag:3];
	} else if (interval == EVERY_WEEK) {
		[updateTypeMatrix selectCellWithTag:2];
	} else {
		[updateTypeMatrix selectCellWithTag:1];
	}
#if _BETA_MODE
	// 変更できないようにする
	[updateCheckAutoCheck setEnabled:NO];
	[updateTypeMatrix setEnabled:NO];
#else
	[updateBetaTestLabel setHidden:YES];
#endif
}

/*----------------------------------------------------------------------------*
 *  ボタン押下時処理
 *----------------------------------------------------------------------------*/

- (IBAction)buttonPressed:(id)sender {
	// パスワード変更ボタン（シートオープン）
	if (sender == basePasswordButton) {
		NSString* password = [Config sharedConfig].password;
		// フィールドの内容を最新に
		[pwdSheetOldPwdField setEnabled:NO];
		[pwdSheet setInitialFirstResponder:pwdSheetNewPwdField1];
		if (password) {
			if ([password length] > 0) {
				[pwdSheetOldPwdField setEnabled:YES];
				[pwdSheet setInitialFirstResponder:pwdSheetOldPwdField];
			}
		}
		[pwdSheetOldPwdField setStringValue:@""];
		[pwdSheetNewPwdField1 setStringValue:@""];
		[pwdSheetNewPwdField2 setStringValue:@""];
		[pwdSheetErrorLabel setStringValue:@""];
		// シート表示
		[NSApp beginSheet:pwdSheet
		   modalForWindow:panel
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:nil];
	}
	// パスワード変更シート変更（OK）ボタン
	else if (sender == pwdSheetOKButton) {
		NSString*	oldPwd		= [pwdSheetOldPwdField stringValue];
		NSString*	newPwd1		= [pwdSheetNewPwdField1 stringValue];
		NSString*	newPwd2		= [pwdSheetNewPwdField2 stringValue];
		NSString*	password	= [Config sharedConfig].password;
		[pwdSheetErrorLabel setStringValue:@""];
		// 旧パスワードチェック
		if (password) {
			if ([password length] > 0) {
				if ([oldPwd length] <= 0) {
					[pwdSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.PwdMod.NoOldPwd", nil)];
					return;
				}
				if (![password isEqualToString:[NSString stringWithCString:crypt([oldPwd UTF8String], "IP") encoding:NSUTF8StringEncoding]] &&
					![password isEqualToString:oldPwd]) {
					// 平文とも比較するのはv0.4までとの互換性のため
					[pwdSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.PwdMod.OldPwdErr", nil)];
					return;
				}
			}
		}
		// 新パスワード２回入力チェック
		if (![newPwd1 isEqualToString:newPwd2]) {
			[pwdSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.PwdMod.NewPwdErr", nil)];
			return;
		}
		// ここまでくれば正しいのでパスワード値変更
		if ([newPwd1 length] > 0) {
			[Config sharedConfig].password	= [NSString stringWithCString:crypt([newPwd1 UTF8String], "IP") encoding:NSUTF8StringEncoding];
		} else {
			[Config sharedConfig].password	= @"";
		}
		[NSApp endSheet:pwdSheet returnCode:NSOKButton];
	}
	// パスワード変更シートキャンセルボタン
	else if (sender == pwdSheetCancelButton) {
		[NSApp endSheet:pwdSheet returnCode:NSCancelButton];
	}
	// ブロードキャストアドレス追加ボタン（シートオープン）
	else if (sender == netBroadAddButton) {
		// フィールドの内容を初期化
		[bcastSheetField setStringValue:@""];
		[bcastSheetErrorLabel setStringValue:@""];
		[bcastSheetMatrix selectCellAtRow:0 column:0];
		[bcastSheetResolveCheck setEnabled:NO];
		[bcastSheet setInitialFirstResponder:bcastSheetField];

		// シート表示
		[NSApp beginSheet:bcastSheet
		   modalForWindow:panel
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:nil];
	}
	// ブロードキャストアドレス削除ボタン
	else if (sender == netBroadDeleteButton) {
		int index = [netBroadAddressTable selectedRow];
		if (index != -1) {
			[[Config sharedConfig] removeBroadcastAtIndex:index];
			[netBroadAddressTable reloadData];
			[netBroadAddressTable deselectAll:self];
		}
	}
	// ブロードキャストシートOKボタン
	else if (sender == bcastSheetOKButton) {
		Config*		config	= [Config sharedConfig];
		NSString*	string	= [bcastSheetField stringValue];
		BOOL		ip		= ([bcastSheetMatrix selectedColumn] == 0);
		// 入力文字列チェック
		if ([string length] <= 0) {
			if (ip) {
				[bcastSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Broadcast.EmptyIP", nil)];
			} else {
				[bcastSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Broadcast.EmptyHost", nil)];
			}
			return;
		}
		// IPアドレス設定の場合
		if (ip) {
			unsigned long 	inetaddr = inet_addr([string UTF8String]);
			struct in_addr	addr;
			NSString*		strAddr;
			if (inetaddr == INADDR_NONE) {
				[bcastSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Broadcast.WrongIP", nil)];
				return;
			}
			addr.s_addr = inetaddr;
			strAddr		= [NSString stringWithCString:inet_ntoa(addr) encoding:NSUTF8StringEncoding];
			if ([config containsBroadcastWithAddress:strAddr]) {
				[bcastSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Broadcast.ExistIP", nil)];
				return;
			}
			[config addBroadcastWithAddress:strAddr];
		}
		// ホスト名設定の場合
		else {
			// アドレス確認
			if ([bcastSheetResolveCheck state]) {
				if (![[NSHost hostWithName:string] address]) {
					[bcastSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Broadcast.UnknownHost", nil)];
					return;
				}
			}
			if ([config containsBroadcastWithHost:string]) {
				[bcastSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Broadcast.ExistHost", nil)];
				return;
			}
			[config addBroadcastWithHost:string];
		}
		[bcastSheetErrorLabel setStringValue:@""];
		[netBroadAddressTable reloadData];
		[NSApp endSheet:bcastSheet returnCode:NSOKButton];
	}
	// ブロードキャストシートキャンセルボタン
	else if (sender == bcastSheetCancelButton) {
		[NSApp endSheet:bcastSheet returnCode:NSCancelButton];
	}
	// 不在追加ボタン／編集ボタン
	else if ((sender == absenceAddButton) || (sender == absenceEditButton)) {
		NSString* title		= @"";
		NSString* msg		= @"";
		absenceEditIndex	= -1;
		if (sender == absenceEditButton) {
			Config* config		= [Config sharedConfig];
			absenceEditIndex	= [absenceTable selectedRow];
			title				= [config absenceTitleAtIndex:absenceEditIndex];
			msg					= [config absenceMessageAtIndex:absenceEditIndex];
		}
		// フィールドの内容を初期化
		[absenceSheetTitleField setStringValue:title];
		[absenceSheetMessageArea setString:msg];
		[absenceSheetErrorLabel setStringValue:@""];
		[absenceSheet setInitialFirstResponder:absenceSheetTitleField];

		// シート表示
		[NSApp beginSheet:absenceSheet
		   modalForWindow:panel
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:nil];
	}
	// 不在削除ボタン
	else if (sender == absenceDeleteButton) {
		Config*		config	= [Config sharedConfig];
		NSInteger	absIdx	= config.absenceIndex;
		NSInteger	rmvIdx	= [absenceTable selectedRow];
		[config removeAbsenceAtIndex:rmvIdx];
		if (rmvIdx == absIdx) {
			config.absenceIndex = -1;
			[[MessageCenter sharedCenter] broadcastAbsence];
		} else if (rmvIdx < absIdx) {
			config.absenceIndex = absIdx - 1;
		}
		[absenceTable reloadData];
		[absenceTable deselectAll:self];
		[[NSApp delegate] buildAbsenceMenu];
	}
	// 不在上へボタン
	else if (sender == absenceUpButton) {
		Config*		config	= [Config sharedConfig];
		NSInteger	absIdx	= config.absenceIndex;
		NSInteger	upIdx	= [absenceTable selectedRow];
		[config upAbsenceAtIndex:upIdx];
		if (upIdx == absIdx) {
			config.absenceIndex = absIdx - 1;
		} else if (upIdx == absIdx + 1) {
			config.absenceIndex = absIdx + 1;
		}
		[absenceTable reloadData];
		[absenceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:upIdx-1] byExtendingSelection:NO];
		[[NSApp delegate] buildAbsenceMenu];
	}
	// 不在下へボタン
	else if (sender == absenceDownButton) {
		Config* config	= [Config sharedConfig];
		NSInteger	absIdx	= config.absenceIndex;
		NSInteger	downIdx	= [absenceTable selectedRow];
		NSInteger	index	= [absenceTable selectedRow];
		[config downAbsenceAtIndex:downIdx];
		if (downIdx == absIdx) {
			config.absenceIndex = absIdx + 1;
		} else if (downIdx == absIdx - 1) {
			config.absenceIndex = absIdx - 1;
		}
		[absenceTable reloadData];
		[absenceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index+1] byExtendingSelection:NO];
		[[NSApp delegate] buildAbsenceMenu];
	}
	// 不在定義初期化ボタン
	else if (sender == absenceResetButton) {
		// 不在モードを解除して送信するか確認
		NSBeginCriticalAlertSheet(	NSLocalizedString(@"Pref.AbsenceReset.Title", nil),
									NSLocalizedString(@"Pref.AbsenceReset.OK", nil),
									NSLocalizedString(@"Pref.AbsenceReset.Cancel", nil),
									nil,
									panel,
									self,
									@selector(sheetDidEnd:returnCode:contextInfo:),
									nil,
									sender,
									NSLocalizedString(@"Pref.AbsenceReset.Msg", nil));
	}
	// 不在シートOKボタン
	else if (sender == absenceSheetOKButton) {
		Config*		config	= [Config sharedConfig];
		NSString*	title	= [absenceSheetTitleField stringValue];
		NSString*	msg		= [NSString stringWithString:[absenceSheetMessageArea string]];
		NSInteger	index	= [absenceTable selectedRow];
		NSInteger	absIdx	= config.absenceIndex;
		[absenceSheetErrorLabel setStringValue:@""];
		// タイトルチェック
		if ([title length] <= 0) {
			[absenceSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Absence.NoTitle", nil)];
			return;
		}
		if ([msg length] <= 0) {
			[absenceSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Absence.NoMessage", nil)];
			return;
		}
		if (absenceEditIndex == -1) {
			if ([config containsAbsenceTitle:title]) {
				[absenceSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Absence.ExistTitle", nil)];
				return;
			}
			if (index == -1) {
				[config addAbsenceTitle:title message:msg];
			} else {
				[config insertAbsenceTitle:title message:msg atIndex:index];
			}
			if ((index != -1) && (absIdx != -1) && (index <= absIdx)) {
				config.absenceIndex = absIdx + 1;
			}
		} else {
			[config setAbsenceTitle:title message:msg atIndex:index];
			if (absIdx == index) {
				[[MessageCenter sharedCenter] broadcastAbsence];
			}
		}
		[absenceTable reloadData];
		[absenceTable deselectAll:self];
		[absenceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:((index == -1) ? 0 : (index))]
				  byExtendingSelection:NO];
		[[NSApp delegate] buildAbsenceMenu];
		[NSApp endSheet:absenceSheet returnCode:NSOKButton];
	}
	// 不在シートCancelボタン
	else if (sender == absenceSheetCancelButton) {
		[NSApp endSheet:absenceSheet returnCode:NSCancelButton];
	}
	// 通知拒否追加ボタン／編集ボタン
	else if ((sender == refuseAddButton) || (sender == refuseEditButton)) {
		IPRefuseTarget		target		= 0;
		NSString* 			string		= @"";
		IPRefuseCondition	condition	= 0;

		refuseEditIndex	= -1;
		if (sender == refuseEditButton) {
			RefuseInfo*	info;
			refuseEditIndex	= [refuseTable selectedRow];
			info			= [[Config sharedConfig] refuseInfoAtIndex:refuseEditIndex];
			target			= [info target];
			string			= [info string];
			condition		= [info condition];
		}
		// フィールドの内容を初期化
		[refuseSheetField setStringValue:string];
		[refuseSheetTargetPopup selectItemAtIndex:target];
		[refuseSheetCondPopup selectItemAtIndex:condition];
		[refuseSheetErrorLabel setStringValue:@""];
		[refuseSheet setInitialFirstResponder:refuseSheetTargetPopup];

		// シート表示
		[NSApp beginSheet:refuseSheet
		   modalForWindow:panel
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:nil];
	}
	// 通知拒否削除ボタン
	else if (sender == refuseDeleteButton) {
		[[Config sharedConfig] removeRefuseInfoAtIndex:[refuseTable selectedRow]];
		[refuseTable reloadData];
		[refuseTable deselectAll:self];
// broadcast entry?
	}
	// 通知拒否上へボタン
	else if (sender == refuseUpButton) {
		int index = [refuseTable selectedRow];
		[[Config sharedConfig] upRefuseInfoAtIndex:index];
		[refuseTable reloadData];
		[refuseTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index-1] byExtendingSelection:NO];
// broadcast entry?
	}
	// 通知拒否下へボタン
	else if (sender == refuseDownButton) {
		int index = [refuseTable selectedRow];
		[[Config sharedConfig] downRefuseInfoAtIndex:index];
		[refuseTable reloadData];
		[refuseTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index+1] byExtendingSelection:NO];
// broadcast entry?
	}
	// 通知拒否シートOKボタン
	else if (sender == refuseSheetOKButton) {
		Config*				cfg			= [Config sharedConfig];
		IPRefuseTarget		target		= [refuseSheetTargetPopup indexOfSelectedItem];
		NSString*			string		= [refuseSheetField stringValue];
		IPRefuseCondition	condition	= [refuseSheetCondPopup indexOfSelectedItem];
		NSInteger			index		= [refuseTable selectedRow];
		RefuseInfo*			info;
		// 入力文字チェック
		if ([string length] <= 0) {
			[refuseSheetErrorLabel setStringValue:NSLocalizedString(@"Pref.Refuse.Error.NoInput", nil)];
			return;
		}

		info = [[[RefuseInfo alloc] initWithTarget:target string:string condition:condition] autorelease];
		if (refuseEditIndex == -1) {
			// 新規
			if (index == -1) {
				[cfg addRefuseInfo:info];
			} else {
				[cfg insertRefuseInfo:info atIndex:index];
			}
			[refuseTable deselectAll:self];
		} else {
			// 変更
			[cfg setRefuseInfo:info atIndex:refuseEditIndex];
		}
		[refuseTable reloadData];
		[NSApp endSheet:refuseSheet returnCode:NSOKButton];
	}
	// 通知拒否シートCancelボタン
	else if (sender == refuseSheetCancelButton) {
		[NSApp endSheet:refuseSheet returnCode:NSCancelButton];
	}
	// 標準ログファイル参照ボタン／重要ログファイル参照ボタン
	else if ((sender == logStdPathRefButton) || (sender == logAltPathRefButton)) {
		NSSavePanel*	sp = [NSSavePanel savePanel];
		NSString*		orgPath;
		// SavePanel 設定
		if (sender == logStdPathRefButton) {
			orgPath = [Config sharedConfig].standardLogFile;
		} else {
			orgPath = [Config sharedConfig].alternateLogFile;
		}
		sp.prompt				= NSLocalizedString(@"Log.File.SaveSheet.OK", nil);
		sp.directoryURL			= [NSURL fileURLWithPath:[orgPath stringByDeletingLastPathComponent]];
		sp.nameFieldStringValue = [orgPath lastPathComponent];
		// シート表示
		[sp beginSheetModalForWindow:panel completionHandler:^(NSInteger result) {
			if (result == NSOKButton) {
				NSString* fn = [sp.URL.path stringByAbbreviatingWithTildeInPath];
				// 標準ログ選択
				if (sender == logStdPathRefButton) {
					[Config sharedConfig].standardLogFile = fn;
					[logStdPathField setStringValue:fn];
				}
				// 重要ログ選択
				else {
					[Config sharedConfig].alternateLogFile = fn;
					[logAltPathField setStringValue:fn];
				}
			}
		}];
	}
	// その他（バグ）
	else {
		ERR(@"unknwon button pressed. %@", sender);
	}
}

/*----------------------------------------------------------------------------*
 *  Matrix変更時処理
 *----------------------------------------------------------------------------*/

- (IBAction)matrixChanged:(id)sender {
	Config* config = [Config sharedConfig];
	// 受信：ノンポップアップ受信モード
	if (sender == receiveNonPopupModeMatrix) {
		config.nonPopupWhenAbsence = ([receiveNonPopupModeMatrix selectedRow] == 1);
	}
	// 受信：ノンポップアップ時アイコンバウンド設定
	else if (sender == receiveNonPopupBoundMatrix) {
		config.iconBoundModeInNonPopup = [[sender selectedCell] tag];
	}
	// ブロードキャスト種別
	else if (sender == bcastSheetMatrix) {
		[bcastSheetResolveCheck setEnabled:([bcastSheetMatrix selectedColumn] == 1)];
	}
	// アップデートチェック種別
	else if (sender == updateTypeMatrix) {
		switch ([[sender selectedCell] tag]) {
			case 1:
				config.updateCheckInterval = EVERY_DAY;
				break;
			case 2:
				config.updateCheckInterval = EVERY_WEEK;
				break;
			case 3:
				config.updateCheckInterval = EVERY_MONTH;
				break;
		}
	}
	// その他
	else {
		ERR(@"unknown matrix changed. %@", sender);
	}
}

/*----------------------------------------------------------------------------*
 *  テキストフィールド変更時処理
 *----------------------------------------------------------------------------*/

- (BOOL)control:(NSControl*)control textShouldEndEditing:(NSText*)fieldEditor {
	// 全般：ユーザ名
	if (control == baseUserNameField) {
		NSRange r = [[fieldEditor string] rangeOfString:@":"];
		if (r.location != NSNotFound) {
			return NO;
		}
	}
	// 全般：グループ名
	else if (control == baseGroupNameField) {
		NSRange r = [[fieldEditor string] rangeOfString:@":"];
		if (r.location != NSNotFound) {
			return NO;
		}
	}
	return YES;
}

- (void)controlTextDidEndEditing:(NSNotification*)aNotification {
	Config* config	= [Config sharedConfig];
	id		obj		= [aNotification object];
	// 全般：ユーザ名
	if (obj == baseUserNameField) {
		config.userName	= [baseUserNameField stringValue];
		[[MessageCenter sharedCenter] broadcastAbsence];
	}
	// 全般：グループ名
	else if (obj == baseGroupNameField) {
		config.groupName = [baseGroupNameField stringValue];
		[[MessageCenter sharedCenter] broadcastAbsence];
	}
	// 全般：ポート番号
	else if (obj == netPortNoField) {
		config.portNo = [netPortNoField integerValue];
	}
	// 送信：引用文字列
	else if (obj == sendQuotField) {
		config.quoteString	= [sendQuotField stringValue];
	}
	// ログ：標準ログ
	else if (obj == logStdPathField) {
		NSString* path = [logStdPathField stringValue];
		config.standardLogFile = path;
		[LogManager standardLog].filePath	= path;
		if (config.standardLogEnabled) {
			AppControl* appCtl = (AppControl*)[NSApp delegate];
			[appCtl checkLogConversion:YES path:path];
		}
	}
	// ログ：重要ログ
	else if (obj == logAltPathField) {
		NSString* path = [logAltPathField stringValue];
		config.alternateLogFile = path;
		[LogManager alternateLog].filePath	= path;
		if (config.alternateLogEnabled) {
			AppControl* appCtl = (AppControl*)[NSApp delegate];
			[appCtl checkLogConversion:NO path:path];
		}
	}
	// その他（バグ）
	else {
		ERR(@"unknwon text end edit. %@", obj);
	}
}

/*----------------------------------------------------------------------------*
 *  チェックボックス変更時処理
 *----------------------------------------------------------------------------*/

- (IBAction)checkboxChanged:(id)sender {
	Config* config = [Config sharedConfig];
	// 全般：ステータスバーを使用するか
	if (sender == receiveStatusBarCheckBox) {
		AppControl* appCtl = (AppControl*)[NSApp delegate];
		config.useStatusBar = [receiveStatusBarCheckBox state];
		if (config.useStatusBar) {
			[appCtl initStatusBar];
		} else {
			[appCtl removeStatusBar];
		}
	}
	// 送信：DOCKのシングルクリックで新規送信ウィンドウ
	else if (sender == sendSingleClickCheck) {
		config.openNewOnDockClick = [sendSingleClickCheck state];
	}
	// 送信：引用チェックをデフォルト
	else if (sender == sendDefaultSealCheck) {
		config.sealCheckDefault = [sendDefaultSealCheck state];
	}
	// 送信：返信時に受信ウィンドウをクローズ
	else if (sender == sendHideWhenReplyCheck) {
		config.hideReceiveWindowOnReply = [sendHideWhenReplyCheck state];
	}
	// 送信：開封通知を行う
	else if (sender == sendOpenNotifyCheck) {
		config.noticeSealOpened = [sendOpenNotifyCheck state];
	}
	// 送信：複数ユーザ宛送信を許可
	else if (sender == sendMultipleUserCheck) {
		config.allowSendingToMultiUser = [sendMultipleUserCheck state];
	}
	// 受信：引用チェックをデフォルト
	else if (sender == receiveDefaultQuotCheck) {
		config.quoteCheckDefault = [receiveDefaultQuotCheck state];
	}
	// 受信：ノンポップアップ受信
	else if (sender == receiveNonPopupCheck) {
		config.nonPopup = [receiveNonPopupCheck state];
		[receiveNonPopupModeMatrix setEnabled:[receiveNonPopupCheck state]];
		[receiveNonPopupBoundMatrix setEnabled:[receiveNonPopupCheck state]];
	}
	// 受信：クリッカブルURL
	else if (sender == receiveClickableURLCheck) {
		config.useClickableURL = [receiveClickableURLCheck state];
	}
	// ネットワーク：ダイアルアップ接続
	else if (sender == netDialupCheck) {
		config.dialup = [netDialupCheck state];
	}
	// ログ：標準ログを使用する
	else if (sender == logStdEnableCheck) {
		BOOL enable = [logStdEnableCheck state];
		config.standardLogEnabled = enable;
		if (enable) {
			AppControl* appCtl = (AppControl*)[NSApp delegate];
			[appCtl checkLogConversion:YES path:[logStdPathField stringValue]];
		}
		[logStdPathField setEnabled:enable];
		[logStdWhenOpenChainCheck setEnabled:enable];
		[logStdPathRefButton setEnabled:enable];
	}
	// ログ：錠前付きは開封後にログ
	else if (sender == logStdWhenOpenChainCheck) {
		config.logChainedWhenOpen = [logStdWhenOpenChainCheck state];
	}
	// ログ：重要ログを使用する
	else if (sender == logAltEnableCheck) {
		BOOL enable = [logAltEnableCheck state];
		config.alternateLogEnabled	= enable;
		if (enable) {
			AppControl* appCtl = (AppControl*)[NSApp delegate];
			[appCtl checkLogConversion:NO path:[logAltPathField stringValue]];
		}
		[logAltPathField setEnabled:enable];
		[logAltSelectionCheck setEnabled:enable];
		[logAltPathRefButton setEnabled:enable];
	}
	// ログ：選択範囲を記録
	else if (sender == logAltSelectionCheck) {
		config.logWithSelectedRange = [logAltSelectionCheck state];
	}
	// アップデート：自動チェック
	else if (sender == updateCheckAutoCheck) {
		BOOL check = ([updateCheckAutoCheck state] == NSOnState);
		config.updateAutomaticCheck = check;
		[updateTypeMatrix setEnabled:check];
	}
	// 不明（バグ）
	else {
		ERR(@"unknwon chackbox changed. %@", sender);
	}
}

/*----------------------------------------------------------------------------*
 *  プルダウン変更時処理
 *----------------------------------------------------------------------------*/

- (IBAction)popupChanged:(id)sender {
	Config* config = [Config sharedConfig];
	// 受信音
	if (sender == receiveSoundPopup) {
		if ([receiveSoundPopup indexOfSelectedItem] > 0) {
			config.receiveSoundName = [receiveSoundPopup titleOfSelectedItem];
			[config.receiveSound play];
		} else {
			config.receiveSoundName = nil;
		}
	}
	// その他（バグ）
	else {
		ERR(@"unknown popup changed. %@", sender);
	}
}

/*----------------------------------------------------------------------------*
 *  リスト選択変更時処理
 *----------------------------------------------------------------------------*/

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	id tbl = [aNotification object];
	// ブロードキャストリスト
	if (tbl == netBroadAddressTable) {
		// １つ以上のアドレスが選択されていない場合は削除ボタンが押下不可
		[netBroadDeleteButton setEnabled:([netBroadAddressTable numberOfSelectedRows] > 0)];
	}
	// 不在リスト
	else if (tbl == absenceTable) {
		int index = [absenceTable selectedRow];
		[absenceEditButton setEnabled:(index != -1)];
		[absenceDeleteButton setEnabled:(index != -1)];
		[absenceUpButton setEnabled:(index > 0)];
		[absenceDownButton setEnabled:((index >= 0) && (index < [absenceTable numberOfRows] - 1))];
	}
	// 通知拒否リスト
	else if (tbl == refuseTable) {
		int index = [refuseTable selectedRow];
		[refuseEditButton setEnabled:(index != -1)];
		[refuseDeleteButton setEnabled:(index != -1)];
		[refuseUpButton setEnabled:(index > 0)];
		[refuseDownButton setEnabled:((index >= 0) && (index < [refuseTable numberOfRows] - 1))];
	}
	// その他（バグ）
	else {
		ERR(@"unknown table selection changed (%@)", tbl);
	}
}

// テーブルダブルクリック時処理
- (void)tableDoubleClicked:(id)sender {
	int index = [sender selectedRow];
	// 不在定義リスト
	if (sender == absenceTable) {
		if (index >= 0) {
			[absenceEditButton performClick:self];
		}
	}
	// 通知拒否条件リスト
	else if (sender == refuseTable) {
		if (index >= 0) {
			[refuseEditButton performClick:self];
		}
	}
	// その他（バグ）
	else {
		ERR(@"unknown table double clicked (%@)", sender);
	}
}

/*----------------------------------------------------------------------------*
 *  シート終了時処理
 *----------------------------------------------------------------------------*/

- (void)sheetDidEnd:(NSWindow*)sheet returnCode:(int)code contextInfo:(void*)info {
	// 不在定義リセット
	if (info == absenceResetButton) {
		if (code == NSOKButton) {
			[[Config sharedConfig] resetAllAbsences];
			[absenceTable reloadData];
			[absenceTable deselectAll:self];
			[[NSApp delegate] buildAbsenceMenu];
		}
	}
	[sheet orderOut:self];
}

/*----------------------------------------------------------------------------*
 * NSTableDataSourceメソッド
 *----------------------------------------------------------------------------*/

- (int)numberOfRowsInTableView:(NSTableView*)aTableView {
	// ブロードキャスト
	if (aTableView == netBroadAddressTable) {
		return [[Config sharedConfig] numberOfBroadcasts];
	}
	// 不在
	else if (aTableView == absenceTable) {
		return [[Config sharedConfig] numberOfAbsences];
	}
	// 通知拒否
	else if (aTableView == refuseTable) {
		return [[Config sharedConfig] numberOfRefuseInfo];
	}
	// その他（バグ）
	else {
		ERR(@"number of rows in unknown table (%@)", aTableView);
	}
	return 0;
}

- (id)tableView:(NSTableView*)aTableView
		objectValueForTableColumn:(NSTableColumn*)aTableColumn
		row:(int)rowIndex {
	// ブロードキャスト
	if (aTableView == netBroadAddressTable) {
		return [[Config sharedConfig] broadcastAtIndex:rowIndex];
	}
	// 不在
	else if (aTableView == absenceTable) {
		return [[Config sharedConfig] absenceTitleAtIndex:rowIndex];
	}
	// 通知拒否リスト
	else if (aTableView == refuseTable) {
		return [[Config sharedConfig] refuseInfoAtIndex:rowIndex];
	}
	// その他（バグ）
	else {
		ERR(@"object in unknown table (%@)", aTableView);
	}
	return nil;
}

/*----------------------------------------------------------------------------*
 *  その他
 *----------------------------------------------------------------------------*/

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

// 初期化
- (void)awakeFromNib {

	// サウンドプルダウンを準備
	NSFileManager*	fm		= [NSFileManager defaultManager];
	NSArray*		dirs	= NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask, YES);
	int				i, j;

	for (i = 0; i < [dirs count]; i++) {
		NSString*	dir		= [[dirs objectAtIndex:i] stringByAppendingPathComponent:@"Sounds"];
		NSArray*	files	= [fm contentsOfDirectoryAtPath:dir error:NULL];
		if (!files) {
			continue;
		}
		for (j = 0; j < [files count]; j++) {
			[receiveSoundPopup addItemWithTitle:[[files objectAtIndex:j] stringByDeletingPathExtension]];
		}
	}

	// テーブルダブルクリック時設定
	[absenceTable setDoubleAction:@selector(tableDoubleClicked:)];
	[refuseTable setDoubleAction:@selector(tableDoubleClicked:)];

	// テーブルドラッグ設定

	// コントロールの設定値を最新状態に
	[self update];

	// 画面中央に移動
	[panel center];
}

// ウィンドウ表示時
- (void)windowDidBecomeKey:(NSNotification *)aNotification {
	[self update];
}

// ウィンドウクローズ時
- (void)windowWillClose:(NSNotification *)aNotification {
	// 設定を保存
	[[Config sharedConfig] save];
}

@end
