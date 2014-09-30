/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: Config.h
 *	Module		: 初期設定情報管理クラス
 *============================================================================*/

#import <Cocoa/Cocoa.h>

@class UserInfo;
@class RefuseInfo;

/*============================================================================*
 * 定数定義
 *============================================================================*/

// ノンポップアップ受信アイコンバウンド種別
typedef enum
{
	IPMSG_BOUND_ONECE	= 0,
	IPMSG_BOUND_REPEAT	= 1,
	IPMSG_BOUND_NONE	= 2

} IPMsgIconBoundType;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface Config : NSObject
{
	//-------- 不揮発の設定値（永続化必要）　----------------------------
	NSString*				_userName;
	NSString*				_groupName;
	NSString*				_password;
	BOOL					_useStatusBar;
	NSInteger				_portNo;
	BOOL					_dialup;
	NSMutableArray*			_broadcastHostList;
	NSMutableArray*			_broadcastIPList;
	NSArray*				_broadcastAddresses;
	NSString*				_quoteString;
	NSMutableArray*			_absenceList;
	NSMutableArray*			_refuseList;
	BOOL					_openNewOnDockClick;
	BOOL					_sealCheckDefault;
	BOOL					_hideRcvWinOnReply;
	BOOL					_noticeSealOpened;
	BOOL					_allowSendingMultiUser;
	NSFont*					_sendMessageFont;
	NSMutableDictionary*	_sendUserListColDisp;
	NSSound*				_receiveSound;
	BOOL					_quoteCheckDefault;
	BOOL					_nonPopup;
	BOOL					_nonPopupWhenAbsence;
	IPMsgIconBoundType		_nonPopupIconBound;
	BOOL					_useClickableURL;
	NSFont*					_receiveMessageFont;
	BOOL					_standardLogEnabled;
	BOOL					_logChainedWhenOpen;
	NSString*				_standardLogFile;
	BOOL					_alternateLogEnabled;
	BOOL					_logWithSelectedRange;
	NSString*				_alternateLogFile;
	BOOL					_sndSearchUser;
	BOOL					_sndSearchGroup;
	BOOL					_sndSearchHost;
	BOOL					_sndSearchLogon;
	NSSize					_sndWinSize;
	float					_sndWinSplit;
	NSSize					_rcvWinSize;
	//-------- 揮発の設定値（永続化不要）　------------------------------
	NSInteger				_absenceIndex;
	NSFont*					_defaultMessageFont;
	NSArray*				_defaultAbsences;
}

// 全般
@property(copy,readwrite)	NSString*			userName;					// ユーザ名
@property(copy,readwrite)	NSString*			groupName;					// グループ名
@property(copy,readwrite)	NSString*			password;					// パスワード
@property(assign,readwrite)	BOOL				useStatusBar;				// メニューバーの右端にアイコンを追加するか
// ネットワーク
@property(assign,readwrite)	NSInteger			portNo;						// ポート番号
@property(assign,readwrite)	BOOL				dialup;						// ダイアルアップ接続
@property(retain,readonly)	NSArray*			broadcastAddresses;			// ブロードキャストアドレス一覧
// アップデート
@property(assign,readwrite)	BOOL				updateAutomaticCheck;		// 更新自動チェック
@property(assign,readwrite)	NSTimeInterval		updateCheckInterval;		// 更新チェック間隔
// 不在モード
@property(readonly)			BOOL				inAbsence;					// 不在モード中か
@property(assign,readwrite)	NSInteger			absenceIndex;				// 不在モード
// 送信
@property(copy,readwrite)	NSString*			quoteString;				// 引用文字列
@property(assign,readwrite)	BOOL				openNewOnDockClick;			// Dockクリック時送信ウィンドウオープン
@property(assign,readwrite)	BOOL				sealCheckDefault;			// 封書チェックをデフォルト
@property(assign,readwrite)	BOOL				hideReceiveWindowOnReply;	// 送信時受信ウィンドウをクローズ
@property(assign,readwrite)	BOOL				noticeSealOpened;			// 開封確認を行う
@property(assign,readwrite)	BOOL				allowSendingToMultiUser;	// 複数ユーザ宛送信を許可
@property(retain,readwrite)	NSFont*				sendMessageFont;			// 送信ウィンドウメッセージ部フォント
@property(readonly)			NSFont*				defaultSendMessageFont;		// 送信ウィンドウメッセージ標準フォント
// 受信
@property(retain,readonly)	NSSound*			receiveSound;				// 受信音
@property(copy,readwrite)	NSString*			receiveSoundName;			// 受信音名
@property(assign,readwrite)	BOOL				quoteCheckDefault;			// 引用チェックをデフォルト
@property(assign,readwrite)	BOOL				nonPopup;					// ノンポップアップ受信
@property(assign,readwrite)	BOOL				nonPopupWhenAbsence;		// 不在時ノンポップアップ受信
@property(assign,readwrite)	IPMsgIconBoundType	iconBoundModeInNonPopup;	// ノンポップアップ受信時アイコンバウンド種別
@property(assign,readwrite)	BOOL				useClickableURL;			// クリッカブルURLを使用する
@property(retain,readwrite)	NSFont*				receiveMessageFont;			// 受信ウィンドウメッセージ部フォント
@property(readonly)			NSFont*				defaultReceiveMessageFont;	// 受信ウィンドウメッセージ標準フォント
// ログ
@property(assign,readwrite)	BOOL				standardLogEnabled;			// 標準ログを使用する
@property(assign,readwrite)	BOOL				logChainedWhenOpen;			// 錠前付きは開封時にログ
@property(copy,readwrite)	NSString*			standardLogFile;			// 標準ログファイルパス
@property(assign,readwrite)	BOOL				alternateLogEnabled;		// 重要ログを使用する
@property(assign,readwrite)	BOOL				logWithSelectedRange;		// 選択範囲を記録する
@property(copy,readwrite)	NSString*			alternateLogFile;			// 重要ログファイルパス
// 送受信ウィンドウ
@property(assign,readwrite)	NSSize				sendWindowSize;				// 送信ウィンドウサイズ
@property(assign,readwrite)	float				sendWindowSplit;			// 送信ウィンドウ分割位置
@property(assign,readwrite)	BOOL				sendSearchByUserName;		// 送信ユーザ検索（ユーザ名）
@property(assign,readwrite)	BOOL				sendSearchByGroupName;		// 送信ユーザ検索（グループ名）
@property(assign,readwrite)	BOOL				sendSearchByHostName;		// 送信ユーザ検索（ホスト名）
@property(assign,readwrite)	BOOL				sendSearchByLogOnName;		// 送信ユーザ検索（ログオン名）
@property(assign,readwrite)	NSSize				receiveWindowSize;			// 受信ウィンドウサイズ

// ファクトリ
+ (Config*)sharedConfig;

// 永続化
- (void)save;

// ----- getter / setter ------
// ネットワーク
- (NSUInteger)numberOfBroadcasts;
- (NSString*)broadcastAtIndex:(NSUInteger)index;
- (BOOL)containsBroadcastWithAddress:(NSString*)address;
- (BOOL)containsBroadcastWithHost:(NSString*)host;
- (void)addBroadcastWithAddress:(NSString*)address;
- (void)addBroadcastWithHost:(NSString*)host;
- (void)removeBroadcastAtIndex:(NSUInteger)index;

// 不在
- (NSUInteger)numberOfAbsences;
- (NSString*)absenceTitleAtIndex:(NSUInteger)index;
- (NSString*)absenceMessageAtIndex:(NSUInteger)index;
- (BOOL)containsAbsenceTitle:(NSString*)title;
- (void)addAbsenceTitle:(NSString*)title message:(NSString*)msg;
- (void)insertAbsenceTitle:(NSString*)title message:(NSString*)msg atIndex:(NSUInteger)index;
- (void)setAbsenceTitle:(NSString*)title message:(NSString*)msg atIndex:(NSInteger)index;
- (void)upAbsenceAtIndex:(NSUInteger)index;
- (void)downAbsenceAtIndex:(NSUInteger)index;
- (void)removeAbsenceAtIndex:(NSUInteger)index;
- (void)resetAllAbsences;

// 通知拒否
- (NSUInteger)numberOfRefuseInfo;
- (RefuseInfo*)refuseInfoAtIndex:(NSUInteger)index;
- (void)addRefuseInfo:(RefuseInfo*)info;
- (void)insertRefuseInfo:(RefuseInfo*)info atIndex:(NSUInteger)index;
- (void)setRefuseInfo:(RefuseInfo*)info atIndex:(NSUInteger)index;
- (void)upRefuseInfoAtIndex:(NSUInteger)index;
- (void)downRefuseInfoAtIndex:(NSUInteger)index;
- (void)removeRefuseInfoAtIndex:(NSUInteger)index;
- (BOOL)matchRefuseCondition:(UserInfo*)user;

// 送信ウィンドウ設定
- (BOOL)sendWindowUserListColumnHidden:(id)identifier;
- (void)setSendWindowUserListColumn:(id)identifier hidden:(BOOL)hidden;

@end
