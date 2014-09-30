/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: SendControl.h
 *	Module		: 送信メッセージウィンドウコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>

@class UserInfo;
@class RecvMessage;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface SendControl : NSObject
{
	IBOutlet NSWindow*		window;				// 送信ウィンドウ
	IBOutlet NSSplitView*	splitView;
	IBOutlet NSView*		splitSubview1;
	IBOutlet NSView*		splitSubview2;
	IBOutlet NSSearchField*	searchField;		// ユーザ検索フィールド
	IBOutlet NSMenu*		searchMenu;			// ユーザ検索メニュー
	IBOutlet NSTableView*	userTable;			// ユーザ一覧
	IBOutlet NSTextField*	userNumLabel;		// ユーザ数ラベル
	IBOutlet NSButton*		refreshButton;		// 更新ボタン
	IBOutlet NSButton*		passwordCheck;		// 鍵チェックボックス
	IBOutlet NSButton*		sealCheck;			// 封書チェックボックス
	IBOutlet NSTextView*	messageArea;		// メッセージ入力欄
	IBOutlet NSButton*		sendButton;			// 送信ボタン
	IBOutlet NSButton*		attachButton;		// 添付ファイルDrawerトグルボタン
	IBOutlet NSDrawer*		attachDrawer;		// 添付ファイルDrawer
	IBOutlet NSTableView*	attachTable;		// 添付ファイル一覧
	IBOutlet NSButton*		attachAddButton;	// 添付追加ボタン
	IBOutlet NSButton*		attachDelButton;	// 添付削除ボタン
	NSMutableArray*			attachments;		// 添付ファイル
	NSMutableDictionary*	attachmentsDic;		// 添付ファイル辞書
	RecvMessage*			receiveMessage;		// 返信元メッセージ
	NSMutableArray*			users;				// ユーザリスト
	NSPredicate*			userPredicate;		// ユーザ検索フィルタ
	NSMutableArray*			selectedUsers;		// 選択ユーザリスト
	NSLock*					selectedUsersLock;	// 選択ユーザリストロック
}

// 初期化
- (id)initWithSendMessage:(NSString*)msg recvMessage:(RecvMessage*)recv;

// ハンドラ
- (IBAction)buttonPressed:(id)sender;
- (IBAction)checkboxChanged:(id)sender;

- (IBAction)searchUser:(id)sender;
- (IBAction)updateUserSearch:(id)sender;
- (IBAction)searchMenuItemSelected:(id)sender;

- (IBAction)sendPressed:(id)sender;
- (IBAction)sendMessage:(id)sender;
- (IBAction)userListUserMenuItemSelected:(id)sender;
- (IBAction)userListGroupMenuItemSelected:(id)sender;
- (IBAction)userListHostMenuItemSelected:(id)sender;
- (IBAction)userListIPAddressMenuItemSelected:(id)sender;
- (IBAction)userListLogonMenuItemSelected:(id)sender;
- (IBAction)userListVersionMenuItemSelected:(id)sender;
- (void)userListChanged:(NSNotification*)aNotification;

// 添付ファイル
- (void)appendAttachmentByPath:(NSString*)path;

// その他
- (IBAction)updateUserList:(id)sender;
- (NSWindow*)window;
- (void)setAttachHeader;

@end
