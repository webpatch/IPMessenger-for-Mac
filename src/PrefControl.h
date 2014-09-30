/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: PrefControl.h
 *	Module		: 環境設定パネルコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface PrefControl : NSObject
{
	IBOutlet NSPanel*			panel;
	// 全般
	IBOutlet NSTextField*		baseUserNameField;
	IBOutlet NSTextField*		baseGroupNameField;
	IBOutlet NSButton*			basePasswordButton;
	IBOutlet NSPanel*			pwdSheet;
	IBOutlet NSSecureTextField*	pwdSheetOldPwdField;
	IBOutlet NSSecureTextField*	pwdSheetNewPwdField1;
	IBOutlet NSSecureTextField*	pwdSheetNewPwdField2;
	IBOutlet NSTextField*		pwdSheetErrorLabel;
	IBOutlet NSButton*			pwdSheetOKButton;
	IBOutlet NSButton*			pwdSheetCancelButton;
	IBOutlet NSButton*			receiveStatusBarCheckBox;
	// 送信
	IBOutlet NSTextField*		sendQuotField;
	IBOutlet NSButton*			sendSingleClickCheck;
	IBOutlet NSButton*			sendDefaultSealCheck;
	IBOutlet NSButton*			sendHideWhenReplyCheck;
	IBOutlet NSButton*			sendOpenNotifyCheck;
	IBOutlet NSButton*			sendMultipleUserCheck;
	// 受信
	IBOutlet NSPopUpButton*		receiveSoundPopup;
	IBOutlet NSButton*			receiveDefaultQuotCheck;
	IBOutlet NSButton*			receiveNonPopupCheck;
	IBOutlet NSMatrix*			receiveNonPopupModeMatrix;
	IBOutlet NSMatrix*			receiveNonPopupBoundMatrix;
	IBOutlet NSButton*			receiveClickableURLCheck;
	// ネットワーク
	IBOutlet NSTextField*		netPortNoField;
	IBOutlet NSButton*			netDialupCheck;
	IBOutlet NSTableView*		netBroadAddressTable;
	IBOutlet NSButton*			netBroadAddButton;
	IBOutlet NSButton*			netBroadDeleteButton;
	IBOutlet NSPanel*			bcastSheet;
	IBOutlet NSMatrix*			bcastSheetMatrix;
	IBOutlet NSButton*			bcastSheetResolveCheck;
	IBOutlet NSTextField*		bcastSheetField;
	IBOutlet NSTextField*		bcastSheetErrorLabel;
	IBOutlet NSButton*			bcastSheetOKButton;
	IBOutlet NSButton*			bcastSheetCancelButton;
	// 不在
	IBOutlet NSTableView*		absenceTable;
	IBOutlet NSButton*			absenceAddButton;
	IBOutlet NSButton*			absenceEditButton;
	IBOutlet NSButton*			absenceDeleteButton;
	IBOutlet NSButton*			absenceUpButton;
	IBOutlet NSButton*			absenceDownButton;
	IBOutlet NSButton*			absenceResetButton;
	IBOutlet NSPanel*			absenceSheet;
	IBOutlet NSTextField*		absenceSheetTitleField;
	IBOutlet NSTextView*		absenceSheetMessageArea;
	IBOutlet NSTextField*		absenceSheetErrorLabel;
	IBOutlet NSButton*			absenceSheetOKButton;
	IBOutlet NSButton*			absenceSheetCancelButton;
	int							absenceEditIndex;
	// 通知拒否
	IBOutlet NSTableView*		refuseTable;
	IBOutlet NSButton*			refuseAddButton;
	IBOutlet NSButton*			refuseEditButton;
	IBOutlet NSButton*			refuseDeleteButton;
	IBOutlet NSButton*			refuseUpButton;
	IBOutlet NSButton*			refuseDownButton;
	IBOutlet NSPanel*			refuseSheet;
	IBOutlet NSTextField*		refuseSheetField;
	IBOutlet NSPopUpButton*		refuseSheetTargetPopup;
	IBOutlet NSPopUpButton*		refuseSheetCondPopup;
	IBOutlet NSTextField*		refuseSheetErrorLabel;
	IBOutlet NSButton*			refuseSheetOKButton;
	IBOutlet NSButton*			refuseSheetCancelButton;
	int							refuseEditIndex;
	// ログ
	IBOutlet NSButton*			logStdEnableCheck;
	IBOutlet NSButton*			logStdWhenOpenChainCheck;
	IBOutlet NSTextField*		logStdPathField;
	IBOutlet NSButton*			logStdPathRefButton;
	IBOutlet NSButton*			logAltEnableCheck;
	IBOutlet NSButton*			logAltSelectionCheck;
	IBOutlet NSTextField*		logAltPathField;
	IBOutlet NSButton*			logAltPathRefButton;
	// アップデート
	IBOutlet NSButton*			updateCheckAutoCheck;
	IBOutlet NSMatrix*			updateTypeMatrix;
	IBOutlet NSTextField*		updateBetaTestLabel;
}

// 最新状態に更新
- (void)update;

// イベントハンドラ
- (IBAction)buttonPressed:(id)sender;
- (IBAction)checkboxChanged:(id)sender;
- (IBAction)popupChanged:(id)sender;
- (IBAction)matrixChanged:(id)sender;

@end
