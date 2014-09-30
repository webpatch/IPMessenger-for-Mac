/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: SendControl.m
 *	Module		: 送信メッセージウィンドウコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import "SendControl.h"
#import "AppControl.h"
#import "Config.h"
#import "LogManager.h"
#import "UserInfo.h"
#import "UserManager.h"
#import "RecvMessage.h"
#import "SendMessage.h"
#import "Attachment.h"
#import "AttachmentFile.h"
#import "AttachmentServer.h"
#import "MessageCenter.h"
#import "WindowManager.h"
#import "ReceiveControl.h"
#import "DebugLog.h"

#define _SEARCH_MENUITEM_TAG_USER		(0)
#define _SEARCH_MENUITEM_TAG_GROUP		(1)
#define _SEARCH_MENUITEM_TAG_HOST		(2)
#define _SEARCH_MENUITEM_TAG_LOGON		(3)

static NSImage*				attachmentImage		= nil;
static NSDate*				lastTimeOfEntrySent	= nil;
static NSMutableDictionary*	userListColumns		= nil;
static NSRecursiveLock*		userListColsLock	= nil;

@interface SendControl()
- (void)updateSearchFieldPlaceholder;
@end


/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation SendControl

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)initWithSendMessage:(NSString*)msg recvMessage:(RecvMessage*)recv {
	self = [super init];

	if (userListColumns == nil) {
		userListColumns		= [[NSMutableDictionary alloc] init];
	}
	if (userListColsLock == nil) {
		userListColsLock	= [[NSRecursiveLock alloc] init];
	}
	users				= [[[UserManager sharedManager] users] mutableCopy];
	selectedUsers		= [[NSMutableArray alloc] init];
	selectedUsersLock	= [[NSLock alloc] init];
	receiveMessage		= [recv retain];
	attachments			= [[NSMutableArray alloc] init];
	attachmentsDic		= [[NSMutableDictionary alloc] init];

	// Nibファイルロード
	if (![NSBundle loadNibNamed:@"SendWindow.nib" owner:self]) {
		[self autorelease];
		return nil;
	}

	// 引用メッセージの設定
	if (msg) {
		if ([msg length] > 0) {
			// 引用文字列行末の改行がなければ追加
			if ([msg characterAtIndex:[msg length] - 1] != '\n') {
				[messageArea insertText:[msg stringByAppendingString:@"\n"]];
			} else {
				[messageArea insertText:msg];
			}
		}
	}

	// ユーザ数ラベルの設定
	[self userListChanged:nil];

	// 添付機能ON/OFF
	[attachButton setEnabled:[AttachmentServer isAvailable]];

	// 添付ヘッダカラム名設定
	[self setAttachHeader];

	// 送信先ユーザの選択
	if (receiveMessage) {
		NSUInteger index = [users indexOfObject:[receiveMessage fromUser]];
		if (index != NSNotFound) {
			[userTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
				   byExtendingSelection:[Config sharedConfig].allowSendingToMultiUser];
			[userTable scrollRowToVisible:index];
		}
	}

	// ウィンドウマネージャへの登録
	if (receiveMessage) {
		[[WindowManager sharedManager] setReplyWindow:self forKey:receiveMessage];
	}

	// ユーザリスト変更の通知登録
	NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self
		   selector:@selector(userListChanged:)
			   name:NOTICE_USER_LIST_CHANGED
			 object:nil];

	// ウィンドウ表示
	[window makeKeyAndOrderFront:self];
	// ファーストレスポンダ設定
	[window makeFirstResponder:messageArea];

	return self;
}

// 解放
- (void)dealloc {
	[users release];
	[userPredicate release];
	[selectedUsers release];
	[selectedUsersLock release];
	[receiveMessage release];
	[attachments release];
	[attachmentsDic release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * ボタン／チェックボックス操作
 *----------------------------------------------------------------------------*/

- (IBAction)buttonPressed:(id)sender {
	// 更新ボタン
	if (sender == refreshButton) {
		[self updateUserList:nil];
	}
	// 添付追加ボタン
	else if (sender == attachAddButton) {
		// 添付追加／削除ボタンを押せなくする
		[attachAddButton setEnabled:NO];
		[attachDelButton setEnabled:NO];
		// シート表示
		NSOpenPanel* op = [NSOpenPanel openPanel];
		op.canChooseDirectories = YES;
		[op beginSheetModalForWindow:window completionHandler:^(NSInteger result) {
			if (result == NSOKButton) {
				for (NSURL* url in op.URLs) {
					[self appendAttachmentByPath:url.path];
				}
			}
			[attachAddButton setEnabled:YES];
			[attachDelButton setEnabled:([attachTable numberOfSelectedRows] > 0)];
		}];
	}
	// 添付削除ボタン
	else if (sender == attachDelButton) {
		int selIdx = [attachTable selectedRow];
		if (selIdx >= 0) {
			Attachment* info = [attachments objectAtIndex:selIdx];
			[attachmentsDic removeObjectForKey:[info file].path];
			[attachments removeObjectAtIndex:selIdx];
			[attachTable reloadData];
			[self setAttachHeader];
		}
	} else {
		ERR(@"unknown button pressed(%@)", sender);
	}
}

- (IBAction)checkboxChanged:(id)sender {
	// 封書チェックボックスクリック
	if (sender == sealCheck) {
		BOOL state = [sealCheck state];
		// 封書チェックがチェックされているときだけ鍵チェックが利用可能
		[passwordCheck setEnabled:state];
		// 封書チェックのチェックがはずされた場合は鍵のチェックも外す
		if (!state) {
			[passwordCheck setState:NSOffState];
		}
	}
	// 鍵チェックボックス
	else if (sender == passwordCheck) {
		// nop
	} else {
		ERR(@"Unknown button pressed(%@)", sender);
	}
}

// シート終了処理
- (void)sheetDidEnd:(NSWindow*)sheet returnCode:(int)code contextInfo:(void*)info {
	if (info == sendButton) {
		[sheet orderOut:self];
		if (code == NSOKButton) {
			// 不在モードを解除してメッセージを送信
			[[NSApp delegate] setAbsenceOff];
			[self sendMessage:self];
		}
	}
}

// 送信メニュー選択時処理
- (IBAction)sendMessage:(id)sender {
	[self sendPressed:sender];
}

// 送信ボタン押下／送信メニュー選択時処理
- (IBAction)sendPressed:(id)sender {
	SendMessage*	info;
	NSMutableArray*	to;
	NSString*		msg;
	BOOL			sealed;
	BOOL			locked;
	NSIndexSet*		userSet;
	Config*			config = [Config sharedConfig];
	NSUInteger		index;

	if (config.inAbsence) {
		// 不在モードを解除して送信するか確認
		NSBeginAlertSheet(	NSLocalizedString(@"SendDlg.AbsenceOff.Title", nil),
							NSLocalizedString(@"SendDlg.AbsenceOff.OK", nil),
							NSLocalizedString(@"SendDlg.AbsenceOff.Cancel", nil),
							nil,
							window,
							self,
							@selector(sheetDidEnd:returnCode:contextInfo:),
							nil,
							sender,
							NSLocalizedString(@"SendDlg.AbsenceOff.Msg", nil),
								[config absenceTitleAtIndex:config.absenceIndex]);
		return;
	}

	// 送信情報整理
	msg		= [messageArea string];
	sealed	= [sealCheck state];
	locked	= [passwordCheck state];
	to		= [[[NSMutableArray alloc] init] autorelease];
	userSet	= [userTable selectedRowIndexes];
	index	= [userSet firstIndex];
	while (index != NSNotFound) {
		[to addObject:[users objectAtIndex:index]];
		index = [userSet indexGreaterThanIndex:index];
	}
	// 送信情報構築
	info = [SendMessage messageWithMessage:msg
							   attachments:attachments
									  seal:sealed
									  lock:locked];
	// メッセージ送信
	[[MessageCenter sharedCenter] sendMessage:info to:to];
	// ログ出力
	[[LogManager standardLog] writeSendLog:info to:to];
	// 受信ウィンドウ消去（初期設定かつ返信の場合）
	if (config.hideReceiveWindowOnReply) {
		ReceiveControl* receiveWin = [[WindowManager sharedManager] receiveWindowForKey:receiveMessage];
		if (receiveWin) {
			[[receiveWin window] performClose:self];
		}
	}
	// 自ウィンドウを消去
	[window performClose:self];
}

// 選択ユーザ一覧の更新
- (void)updateSelectedUsers {
	if ([selectedUsersLock tryLock]) {
		NSIndexSet*	select	= [userTable selectedRowIndexes];
		NSUInteger	index;
		[selectedUsers removeAllObjects];
		index = [select firstIndex];
		while (index != NSNotFound) {
			[selectedUsers addObject:[users objectAtIndex:index]];
			index = [select indexGreaterThanIndex:index];
		}
		[selectedUsersLock unlock];
	}
}

// SplitViewのリサイズ制限
- (float)splitView				:(NSSplitView*)sender
		  constrainMinCoordinate:(float)proposedMin
					 ofSubviewAt:(int)offset {
	if (offset == 0) {
		// 上側ペインの最小サイズを制限
		return 90;
	}
	return proposedMin;
}

// SplitViewのリサイズ制限
- (float)splitView				:(NSSplitView*)sender
		  constrainMaxCoordinate:(float)proposedMax
					 ofSubviewAt:(int)offset {
	if (offset == 0) {
		// 上側ペインの最大サイズを制限
		return [sender frame].size.height - [sender dividerThickness] - 2;
	}
	return proposedMax;
}

// SplitViewのリサイズ処理
- (void)splitView:(NSSplitView*)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSSize	newSize	= [sender frame].size;
	float	divider	= [sender dividerThickness];
	NSRect	frame1	= [splitSubview1 frame];
	NSRect	frame2	= [splitSubview2 frame];

	frame1.size.width	= newSize.width;
	if (frame1.size.height > newSize.height - divider) {
		// ヘッダ部の高さは変更しないがSplitViewの大きさ内には納める
		frame1.size.height = newSize.height - divider;
	}
	frame2.origin.x		= -1;
	frame2.size.width	= newSize.width + 2;
	frame2.size.height	= newSize.height - frame1.size.height - divider;
	[splitSubview1 setFrame:frame1];
	[splitSubview2 setFrame:frame2];
}

/*----------------------------------------------------------------------------*
 * NSTableDataSourceメソッド
 *----------------------------------------------------------------------------*/

- (int)numberOfRowsInTableView:(NSTableView*)aTableView {
	if (aTableView == userTable) {
		return [users count];
	} else if (aTableView == attachTable) {
		return [attachments count];
	} else {
		ERR(@"Unknown TableView(%@)", aTableView);
	}
	return 0;
}

- (id)tableView:(NSTableView*)aTableView
		objectValueForTableColumn:(NSTableColumn*)aTableColumn
		row:(int)rowIndex {
	if (aTableView == userTable) {
		UserInfo* info = [users objectAtIndex:rowIndex];
		NSString* iden = [aTableColumn identifier];
		if ([iden isEqualToString:kIPMsgUserInfoUserNamePropertyIdentifier]) {
			return info.userName;
		} else if ([iden isEqualToString:kIPMsgUserInfoGroupNamePropertyIdentifier]) {
			return info.groupName;
		} else if ([iden isEqualToString:kIPMsgUserInfoHostNamePropertyIdentifier]) {
			return info.hostName;
		} else if ([iden isEqualToString:kIPMsgUserInfoIPAddressPropertyIdentifier]) {
			return info.ipAddress;
		} else if ([iden isEqualToString:kIPMsgUserInfoLogOnNamePropertyIdentifier]) {
			return info.logOnName;
		} else if ([iden isEqualToString:kIPMsgUserInfoVersionPropertyIdentifer]) {
			return info.version;
		} else {
			ERR(@"Unknown TableColumn(%@)", iden);
		}
	} else if (aTableView == attachTable) {
		Attachment*					attach;
		NSMutableAttributedString*	cellValue;
		NSFileWrapper*				fileWrapper;
		NSTextAttachment*			textAttachment;
		attach = [attachments objectAtIndex:rowIndex];
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

/*----------------------------------------------------------------------------*
 * NSTableViewDelegateメソッド
 *----------------------------------------------------------------------------*/

// ユーザリストの選択変更
- (void)tableViewSelectionDidChange:(NSNotification*)aNotification {
	NSTableView* table = [aNotification object];
	if (table == userTable) {
		int selectNum = [userTable numberOfSelectedRows];
		// 選択ユーザ一覧更新
		[self updateSelectedUsers];
		// １つ以上のユーザが選択されていない場合は送信ボタンが押下不可
		[sendButton setEnabled:(selectNum > 0)];
	} else if (table == attachTable) {
		[attachDelButton setEnabled:([attachTable numberOfSelectedRows] > 0)];
	} else {
		ERR(@"Unknown TableView(%@)", table);
	}
}

// ソートの変更
- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors {
	[users sortUsingDescriptors:[aTableView sortDescriptors]];
	[aTableView reloadData];
}

/*----------------------------------------------------------------------------*
 * 添付ファイル
 *----------------------------------------------------------------------------*/

- (void)appendAttachmentByPath:(NSString*)path {
	AttachmentFile*	file;
	Attachment*		attach;
	file = [AttachmentFile fileWithPath:path];
	if (!file) {
		WRN(@"file invalid(%@)", path);
		return;
	}
	attach = [Attachment attachmentWithFile:file];
	if (!attach) {
		WRN(@"attachement invalid(%@)", path);
		return;
	}
	if ([attachmentsDic objectForKey:path]) {
		WRN(@"already contains attachment(%@)", path);
		return;
	}
	[attachments addObject:attach];
	[attachmentsDic setObject:attach forKey:path];
	[attachTable reloadData];
	[self setAttachHeader];
	[attachDrawer open:self];
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

- (IBAction)searchMenuItemSelected:(id)sender
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		NSInteger	newSt	= ([sender state] == NSOnState) ? NSOffState : NSOnState;
		BOOL		newVal	= (BOOL)(newSt == NSOnState);
		Config*		cfg		= [Config sharedConfig];

		[sender setState:newSt];
		switch ([sender tag]) {
			case _SEARCH_MENUITEM_TAG_USER:
				cfg.sendSearchByUserName = newVal;
				break;
			case _SEARCH_MENUITEM_TAG_GROUP:
				cfg.sendSearchByGroupName = newVal;
				break;
			case _SEARCH_MENUITEM_TAG_HOST:
				cfg.sendSearchByHostName = newVal;
				break;
			case _SEARCH_MENUITEM_TAG_LOGON:
				cfg.sendSearchByLogOnName = newVal;
				break;
			default:
				ERR(@"unknown tag(%d)", [sender tag]);
				break;
		}
		[self updateUserSearch:self];
		[self updateSearchFieldPlaceholder];
	}
}

// ユーザリスト更新
- (IBAction)updateUserList:(id)sender {
	if (!lastTimeOfEntrySent || ([lastTimeOfEntrySent timeIntervalSinceNow] < -2.0)) {
		[[UserManager sharedManager] removeAllUsers];
		[[MessageCenter sharedCenter] broadcastEntry];
	} else {
		DBG(@"Cancel Refresh User(%f)", [lastTimeOfEntrySent timeIntervalSinceNow]);
	}
	[lastTimeOfEntrySent release];
	lastTimeOfEntrySent = [[NSDate date] retain];
}

- (IBAction)userListMenuItemSelected:(id)sender with:(id)identifier {
	NSTableColumn* col = [userTable tableColumnWithIdentifier:identifier];
	if (col) {
		// あるので消す
		[userListColsLock lock];
		[userListColumns setObject:col forKey:identifier];
		[userListColsLock unlock];
		[userTable removeTableColumn:col];
		[sender setState:NSOffState];
		[[Config sharedConfig] setSendWindowUserListColumn:identifier hidden:YES];
	} else {
		// ないので追加する
		[userListColsLock lock];
		[userTable addTableColumn:[userListColumns objectForKey:identifier]];
		[userListColsLock unlock];
		[sender setState:NSOnState];
		[[Config sharedConfig] setSendWindowUserListColumn:identifier hidden:NO];
	}
}

- (IBAction)userListUserMenuItemSelected:(id)sender {
	[self userListMenuItemSelected:sender with:kIPMsgUserInfoUserNamePropertyIdentifier];
}

- (IBAction)userListGroupMenuItemSelected:(id)sender {
	[self userListMenuItemSelected:sender with:kIPMsgUserInfoGroupNamePropertyIdentifier];
}

- (IBAction)userListHostMenuItemSelected:(id)sender {
	[self userListMenuItemSelected:sender with:kIPMsgUserInfoHostNamePropertyIdentifier];
}

- (IBAction)userListIPAddressMenuItemSelected:(id)sender {
	[self userListMenuItemSelected:sender with:kIPMsgUserInfoIPAddressPropertyIdentifier];
}

- (IBAction)userListLogonMenuItemSelected:(id)sender {
	[self userListMenuItemSelected:sender with:kIPMsgUserInfoLogOnNamePropertyIdentifier];
}

- (IBAction)userListVersionMenuItemSelected:(id)sender {
	[self userListMenuItemSelected:sender with:kIPMsgUserInfoVersionPropertyIdentifer];
}

// ユーザ一覧変更時処理
- (void)userListChanged:(NSNotification*)aNotification
{
	[users setArray:[[UserManager sharedManager] users]];
	NSInteger totalNum = [users count];
	if (userPredicate) {
		[users filterUsingPredicate:userPredicate];
	}
	[users sortUsingDescriptors:[userTable sortDescriptors]];
	[selectedUsersLock lock];
	// ユーザ数設定
	//[userNumLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"SendDlg.UserNumStr", nil), [users count], totalNum]];
    
    NSString *numStr= [NSString stringWithFormat:NSLocalizedString(@"SendDlg.UserNumStr", nil), [users count], totalNum];
    self.window.title = [@"Send Message " stringByAppendingString:numStr];
	// ユーザリストの再描画
	[userTable reloadData];
	// 再選択
	[userTable deselectAll:self];
	for (UserInfo* user in selectedUsers) {
		NSUInteger index = [users indexOfObject:user];
		if (index != NSNotFound) {
			[userTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
				   byExtendingSelection:[Config sharedConfig].allowSendingToMultiUser];
		}
	}
	[selectedUsersLock unlock];
	[self updateSelectedUsers];
}

- (IBAction)searchUser:(id)sender
{
	NSResponder* firstResponder = [window firstResponder];
	if ([firstResponder isKindOfClass:[NSTextView class]]) {
		NSTextView* tv = (NSTextView*)firstResponder;
		if ([[tv delegate] isKindOfClass:[NSTextField class]]) {
			NSTextField* tf = (NSTextField*)[tv delegate];
			if (tf == searchField) {
				// 検索フィールド（セル内の部品）にフォーカスがある場合はメッセージ領域に移動
				[window makeFirstResponder:messageArea];
				return;
			}
		}
	}
	// 検索フィールドにフォーカスがなければフォーカスを移動
	[window makeFirstResponder:searchField];
}

- (IBAction)updateUserSearch:(id)sender
{
	NSString* searchWord = [searchField stringValue];
	[userPredicate release];
	userPredicate = nil;
	if ([searchWord length] > 0) {
		Config*				cfg	= [Config sharedConfig];
		NSMutableString*	fmt	= [NSMutableString string];
		if (cfg.sendSearchByUserName) {
			[fmt appendFormat:@"%@ contains[c] '%@'", kIPMsgUserInfoUserNamePropertyIdentifier, searchWord];
		}
		if (cfg.sendSearchByGroupName) {
			if ([fmt length] > 0) {
				[fmt appendString:@" OR "];
			}
			[fmt appendFormat:@"%@ contains[c] '%@'", kIPMsgUserInfoGroupNamePropertyIdentifier, searchWord];
		}
		if (cfg.sendSearchByHostName) {
			if ([fmt length] > 0) {
				[fmt appendString:@" OR "];
			}
			[fmt appendFormat:@"%@ contains[c] '%@'", kIPMsgUserInfoHostNamePropertyIdentifier, searchWord];
		}
		if (cfg.sendSearchByLogOnName) {
			if ([fmt length] > 0) {
				[fmt appendString:@" OR "];
			}
			[fmt appendFormat:@"%@ contains[c] '%@'", kIPMsgUserInfoLogOnNamePropertyIdentifier, searchWord];
		}
		[userPredicate release];
		if ([fmt length] > 0) {
			userPredicate = [[NSPredicate predicateWithFormat:fmt] retain];
		}
	}
	[self userListChanged:nil];
}

- (void)updateSearchFieldPlaceholder
{
	Config*			cfg		= [Config sharedConfig];
	NSMutableArray*	array	= [NSMutableArray array];
	if (cfg.sendSearchByUserName) {
		[array addObject:NSLocalizedString(@"SendDlg.Search.Target.User", nil)];
	}
	if (cfg.sendSearchByGroupName) {
		[array addObject:NSLocalizedString(@"SendDlg.Search.Target.Group", nil)];
	}
	if (cfg.sendSearchByHostName) {
		[array addObject:NSLocalizedString(@"SendDlg.Search.Target.Host", nil)];
	}
	if (cfg.sendSearchByLogOnName) {
		[array addObject:NSLocalizedString(@"SendDlg.Search.Target.LogOn", nil)];
	}
	NSString* str = @"";
	if ([array count] > 0) {
		NSString* sep = NSLocalizedString(@"SendDlg.Search.Placeholder.Separator", nil);
		NSString* fmt = NSLocalizedString(@"SendDlg.Search.Placeholder.Normal", nil);
		str = [NSString stringWithFormat:fmt, [array componentsJoinedByString:sep]];
	} else {
		str = NSLocalizedString(@"SendDlg.Search.Placeholder.Invalid", nil);
	}
	[[searchField cell] setPlaceholderString:str];
}

// ウィンドウを返す
- (NSWindow*)window {
	return window;
}

// メッセージ部フォントパネル表示
- (void)showSendMessageFontPanel:(id)sender {
	[[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

// メッセージ部フォント保存
- (void)saveSendMessageFont:(id)sender {
	[Config sharedConfig].sendMessageFont = [messageArea font];
}

// メッセージ部フォントを標準に戻す
- (void)resetSendMessageFont:(id)sender {
	[messageArea setFont:[Config sharedConfig].defaultSendMessageFont];
}

// 送信不可の場合にメニューからの送信コマンドを抑制する
- (BOOL)respondsToSelector:(SEL)aSelector {
	if (aSelector == @selector(sendMessage:)) {
		return [sendButton isEnabled];
	}
	return [super respondsToSelector:aSelector];
}

- (void)setAttachHeader {
	NSString*		format	= NSLocalizedString(@"SendDlg.Attach.Header", nil);
	NSString*		title	= [NSString stringWithFormat:format, [attachments count]];
	[[[attachTable tableColumnWithIdentifier:@"Attachment"] headerCell] setStringValue:title];
}

/*----------------------------------------------------------------------------*
 *  デリゲート
 *----------------------------------------------------------------------------*/

// Nibファイルロード時処理
- (void)awakeFromNib {
	Config*			config		= [Config sharedConfig];
	NSSize			size		= config.sendWindowSize;
	float			splitPoint	= config.sendWindowSplit;
	NSRect			frame		= [window frame];
	int				i;

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

	// SplitViewサイズ決定
	if (splitPoint != 0) {
		// 上部
		frame = [splitSubview1 frame];
		frame.size.height = splitPoint;
		[splitSubview1 setFrame:frame];
		// 下部
		frame = [splitSubview2 frame];
		frame.origin.x		= -1;
		frame.size.width	+= 2;
		frame.size.height = [splitView frame].size.height - splitPoint - [splitView dividerThickness];
		[splitSubview2 setFrame:frame];
		// 全体
		[splitView adjustSubviews];
	}
	frame = [splitSubview2 frame];
	frame.origin.x		= -1;
	frame.size.width	+= 2;
	[splitSubview2 setFrame:frame];

	// 封書チェックをデフォルト判定
	if (config.sealCheckDefault) {
		[sealCheck setState:NSOnState];
		[passwordCheck setEnabled:YES];
	}

	// 複数ユーザへの送信を許可
	[userTable setAllowsMultipleSelection:config.allowSendingToMultiUser];

	// ユーザリストの行間設定（デフォルト[3,2]→[2,1]）
	[userTable setIntercellSpacing:NSMakeSize(2, 1)];

	// ユーザリストのカラム処理
	NSArray* array = [NSArray arrayWithObjects:	kIPMsgUserInfoUserNamePropertyIdentifier,
												kIPMsgUserInfoGroupNamePropertyIdentifier,
												kIPMsgUserInfoHostNamePropertyIdentifier,
												kIPMsgUserInfoIPAddressPropertyIdentifier,
												kIPMsgUserInfoLogOnNamePropertyIdentifier,
												kIPMsgUserInfoVersionPropertyIdentifer,
												nil];
	for (i = 0; i < [array count]; i++) {
		NSString*		identifier	= [array objectAtIndex:i];
		NSTableColumn*	column		= [userTable tableColumnWithIdentifier:identifier];
		if (identifier && column) {
			// カラム保持
			[userListColsLock lock];
			[userListColumns setObject:column forKey:identifier];
			[userListColsLock unlock];
			// 設定値に応じてカラムの削除
			if ([config sendWindowUserListColumnHidden:identifier]) {
				[userTable removeTableColumn:column];
			}
		}
	}

	// ユーザリストのソート設定反映
	[users sortUsingDescriptors:[userTable sortDescriptors]];

	// 検索フィールドのメニュー設定
	[[searchMenu itemWithTag:_SEARCH_MENUITEM_TAG_USER] setState:config.sendSearchByUserName ? NSOnState : NSOffState];
	[[searchMenu itemWithTag:_SEARCH_MENUITEM_TAG_GROUP] setState:config.sendSearchByGroupName ? NSOnState : NSOffState];
	[[searchMenu itemWithTag:_SEARCH_MENUITEM_TAG_HOST] setState:config.sendSearchByHostName ? NSOnState : NSOffState];
	[[searchMenu itemWithTag:_SEARCH_MENUITEM_TAG_LOGON] setState:config.sendSearchByLogOnName ? NSOnState : NSOffState];
	[[searchField cell] setSearchMenuTemplate:searchMenu];
	[self updateSearchFieldPlaceholder];

	// 添付リストの行設定
	[attachTable setRowHeight:16.0];

	// メッセージ部フォント
	if (config.sendMessageFont) {
		[messageArea setFont:config.sendMessageFont];
	}

	// ファイル添付アイコン
	if (!attachmentImage) {
		attachmentImage = [[NSImage alloc] initWithContentsOfFile:
								[[NSBundle mainBundle] pathForResource:@"AttachS" ofType:@"tiff"]];
	}

	// ファーストレスポンダ設定
	[window makeFirstResponder:messageArea];
}

// ウィンドウリサイズ時処理
- (void)windowDidResize:(NSNotification *)notification
{
	// ウィンドウサイズを保存
	[Config sharedConfig].sendWindowSize = [window frame].size;
}

// SplitViewリサイズ時処理
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
	[Config sharedConfig].sendWindowSplit = [splitSubview1 frame].size.height;
}

// ウィンドウクローズ時処理
- (void)windowWillClose:(NSNotification*)aNotification {
	[[WindowManager sharedManager] removeReplyWindowForKey:receiveMessage];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
// なぜか解放されないので手動で
[attachDrawer release];
	[self release];
}

@end
