/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: Config.m
 *	Module		: 初期設定情報管理クラス
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#import <objc/runtime.h>
#import "Config.h"
#import "RefuseInfo.h"
#import "DebugLog.h"

/*============================================================================*
 * 定数定義
 *============================================================================*/

// 基本
static NSString* GEN_VERSION			= @"Version";
static NSString* GEN_VERSION_STR		= @"VersionString";
static NSString* GEN_USER_NAME			= @"UserName";
static NSString* GEN_GROUP_NAME			= @"GroupName";
static NSString* GEN_PASSWORD			= @"UserPassword";
static NSString* GEN_USE_STATUS_BAR		= @"UseStatusBarMenu";

// ネットワーク
static NSString* NET_PORT_NO			= @"PortNo";
static NSString* NET_BROADCAST			= @"Broadcast";
static NSString* NET_DIALUP				= @"Dialup";

// 送信
static NSString* SEND_QUOT_STR			= @"QuotationString";
static NSString* SEND_DOCK_SEND			= @"OpenSendWindowWhenDockClick";
static NSString* SEND_SEAL_CHECK		= @"SealCheckDefaultOn";
static NSString* SEND_HIDE_REPLY		= @"HideRecieveWindowWhenSendReply";
static NSString* SEND_OPENSEAL_CHECK	= @"CheckSealOpened";
static NSString* SEND_MULTI_USER_CHECK	= @"AllowSendingToMutipleUser";
static NSString* SEND_MSG_FONT_NAME		= @"SendMessageFontName";
static NSString* SEND_MSG_FONT_SIZE		= @"SendMessageFontSize";

// 受信
static NSString* RECV_SOUND				= @"ReceiveSound";
static NSString* RECV_QUOT_CHECK		= @"QuotCheckDefaultOn";
static NSString* RECV_NON_POPUP			= @"NonPopupReceive";
static NSString* RECV_ABSENCE_NONPOPUP	= @"NonPopupReceiveWhenAbsenceMode";
static NSString* RECV_BOUND_IN_NONPOPUP	= @"DockIconBoundInNonPopupReceive";
static NSString* RECV_CLICKABLE_URL		= @"UseClickableURL";
static NSString* RECV_MSG_FONT_NAME		= @"ReceiveMessageFontName";
static NSString* RECV_MSG_FONT_SIZE		= @"ReceiveMessageFontSize";

// 不在
static NSString* ABSENCE				= @"Absence";

// 通知拒否
static NSString* REFUSE					= @"RefuseCondition";

// ログ
static NSString* LOG_STD_ON				= @"StandardLogEnabled";
static NSString* LOG_STD_CHAIN			= @"StandardLogWhenLockedMessageOpened";
static NSString* LOG_STD_FILE			= @"StandardLogFile";
static NSString* LOG_ALT_ON				= @"AlternateLogEnabled";
static NSString* LOG_ALT_SELECTION		= @"AlternateLogWithSelectedRange";
static NSString* LOG_ALT_FILE			= @"AlternateLogFile";

// ウィンドウ位置／サイズ／設定
static NSString* RCVWIN_SIZE_W			= @"ReceiveWindowWidth";
static NSString* RCVWIN_SIZE_H			= @"ReceiveWindowHeight";
static NSString* SNDWIN_SIZE_W			= @"SendWindowWidth";
static NSString* SNDWIN_SIZE_H			= @"SendWindowHeight";
static NSString* SNDWIN_SIZE_SPLIT		= @"SendWindowSplitPoint";
static NSString* SNDWIN_USERLIST_COL	= @"SendWindowUserListColumnDisplay";
static NSString* SNDSEARCH_USER			= @"SendWindowSearchByUserName";
static NSString* SNDSEARCH_GROUP		= @"SendWindowSearchByGroupName";
static NSString* SNDSEARCH_HOST			= @"SendWindowSearchByHostName";
static NSString* SNDSEARCH_LOGON		= @"SendWindowSearchByLogOnName";

@interface Config()
- (void)updateBroadcastAddresses;
- (NSMutableArray*)convertRefuseDefaultsToInfo:(NSArray*)array;
- (NSMutableArray*)convertRefuseInfoToDefaults:(NSArray*)array;
@property(retain,readwrite)	NSArray*	broadcastAddresses;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation Config

@synthesize	userName					= _userName;
@synthesize groupName					= _groupName;
@synthesize password					= _password;
@synthesize useStatusBar				= _useStatusBar;
@synthesize portNo						= _portNo;
@synthesize dialup						= _dialup;
@synthesize broadcastAddresses			= _broadcastAddresses;
@synthesize quoteString					= _quoteString;
@synthesize openNewOnDockClick			= _openNewOnDockClick;
@synthesize sealCheckDefault			= _sealCheckDefault;
@synthesize hideReceiveWindowOnReply	= _hideRcvWinOnReply;
@synthesize noticeSealOpened			= _noticeSealOpened;
@synthesize allowSendingToMultiUser		= _allowSendingMultiUser;
@synthesize	receiveSound				= _receiveSound;
@synthesize quoteCheckDefault			= _quoteCheckDefault;
@synthesize nonPopup					= _nonPopup;
@synthesize nonPopupWhenAbsence			= _nonPopupWhenAbsence;
@synthesize iconBoundModeInNonPopup		= _nonPopupIconBound;
@synthesize useClickableURL				= _useClickableURL;
@synthesize standardLogEnabled			= _standardLogEnabled;
@synthesize logChainedWhenOpen			= _logChainedWhenOpen;
@synthesize standardLogFile				= _standardLogFile;
@synthesize alternateLogEnabled			= _alternateLogEnabled;
@synthesize logWithSelectedRange		= _logWithSelectedRange;
@synthesize alternateLogFile			= _alternateLogFile;
@synthesize sendWindowSize				= _sndWinSize;
@synthesize sendWindowSplit				= _sndWinSplit;
@synthesize sendSearchByUserName		= _sndSearchUser;
@synthesize sendSearchByGroupName		= _sndSearchGroup;
@synthesize sendSearchByHostName		= _sndSearchHost;
@synthesize sendSearchByLogOnName		= _sndSearchLogon;
@synthesize receiveWindowSize			= _rcvWinSize;

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/
#pragma mark -

// 共有インスタンスを返す
+ (Config*)sharedConfig
{
	static Config* sharedConfig = nil;
	if (!sharedConfig) {
		sharedConfig = [[Config alloc] init];
	}
	return sharedConfig;
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/
#pragma mark -

// 初期化
- (id)init
{
	self = [super init];
	if (!self) {
		return nil;
	}

	NSUserDefaults*			defaults = [NSUserDefaults standardUserDefaults];
	NSArray*				array;
	NSMutableArray*			mutableArray;
	NSDictionary*			dic;
	NSMutableDictionary*	mutableDic;
	NSString*				str;
	float					fVal;
	NSUInteger				i;
	NSSize					size;

	DBG(@"======== Init Config start ========");

	// デフォルト値の設定
	mutableDic = [NSMutableDictionary dictionary];
	// 全般
	[mutableDic setObject:NSFullUserName() forKey:GEN_USER_NAME];
	[mutableDic setObject:@"" forKey:GEN_GROUP_NAME];
	[mutableDic setObject:@"" forKey:GEN_PASSWORD];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:GEN_USE_STATUS_BAR];
	// ネットワーク
	[mutableDic setObject:[NSNumber numberWithInt:2425] forKey:NET_PORT_NO];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:NET_DIALUP];
	// 送信
	[mutableDic setObject:@">" forKey:SEND_QUOT_STR];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:SEND_DOCK_SEND];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:SEND_SEAL_CHECK];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:SEND_HIDE_REPLY];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:SEND_OPENSEAL_CHECK];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:SEND_MULTI_USER_CHECK];
	// 受信
	[mutableDic setObject:@"" forKey:RECV_SOUND];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:RECV_QUOT_CHECK];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:RECV_NON_POPUP];
	[mutableDic setObject:[NSNumber numberWithInt:IPMSG_BOUND_ONECE] forKey:RECV_BOUND_IN_NONPOPUP];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:RECV_ABSENCE_NONPOPUP];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:RECV_CLICKABLE_URL];
	// ログ
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:LOG_STD_ON];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:LOG_STD_CHAIN];
	[mutableDic setObject:@"~/Documents/ipmsg_log.txt" forKey:LOG_STD_FILE];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:LOG_ALT_ON];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:LOG_ALT_SELECTION];
	[mutableDic setObject:@"~/Documents/ipmsg_alt_log.txt" forKey:LOG_ALT_FILE];
	// 送信ウィンドウ
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:SNDSEARCH_USER];
	[mutableDic setObject:[NSNumber numberWithBool:YES] forKey:SNDSEARCH_GROUP];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:SNDSEARCH_HOST];
	[mutableDic setObject:[NSNumber numberWithBool:NO] forKey:SNDSEARCH_LOGON];
	[defaults registerDefaults:mutableDic];
	#if IPMSG_LOG_TRC
		// デバッグ用ログ出力
		TRC(@"defaultValues[%u]=(", [mutableDic count]);
		for (id key in [mutableDic allKeys]) {
			id val = [mutableDic objectForKey:key];
			array = [[val description] componentsSeparatedByString:@"\n"];
			if ([array count] > 1) {
				NSUInteger num = 0;
				for (NSString* s in array) {
					num++;
					if (num == 1) {
						TRC(@"\t%@=%@", key, s);
					} else {
						TRC(@"\t\t%@", s);
					}
				}
			} else if ([val isKindOfClass:[NSString class]]) {
				TRC(@"\t%@=\"%@\"", key, val);
			} else {
				TRC(@"\t%@=%@", key, val);
			}
		}
		TRC(@")");
	#endif

	// 不在文のデフォルト値
	mutableArray = [NSMutableArray array];
	for (i = 0; i < 8; i++) {
		NSString* key1	= [NSString stringWithFormat:@"Pref.Absence.Def%d.Title", i];
		NSString* key2	= [NSString stringWithFormat:@"Pref.Absence.Def%d.Message", i];
		mutableDic = [NSMutableDictionary dictionary];
		[mutableDic setObject:NSLocalizedString(key1, nil) forKey:@"Title"];
		[mutableDic setObject:NSLocalizedString(key2, nil) forKey:@"Message"];
		[mutableArray addObject:mutableDic];
	}
	_defaultAbsences = [[NSArray alloc] initWithArray:mutableArray];
	#if IPMSG_LOG_TRC
		// デバッグ用ログ出力
		TRC(@"defaultAbsences[%u]=(", [_defaultAbsences count]);
		for (dic in _defaultAbsences) {
			NSString* t = [dic objectForKey:@"Title"];
			NSString* m = [dic objectForKey:@"Message"];
			str = [m stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
			TRC(@"\t\"%@\"（\"%@\"）", t, str);
		}
		TRC(@")");
	#endif

	// フォントのデフォルト値
	str		= NSLocalizedString(@"Message.DefaultFontName", nil);
	fVal	= 12;
	_defaultMessageFont	= [[NSFont fontWithName:str size:fVal] retain];
	if (!_defaultMessageFont) {
		_defaultMessageFont = [[NSFont systemFontOfSize:[NSFont systemFontSize]] retain];
	}
	TRC(@"defaultMessageFont=%@", _defaultMessageFont);

	// 全般
	self.userName					= [defaults stringForKey:GEN_USER_NAME];
	self.groupName					= [defaults stringForKey:GEN_GROUP_NAME];
	self.password					= [defaults stringForKey:GEN_PASSWORD];
	self.useStatusBar				= [defaults boolForKey:GEN_USE_STATUS_BAR];
	// ネットワーク
	self.portNo						= [defaults integerForKey:NET_PORT_NO];
	self.dialup						= [defaults boolForKey:NET_DIALUP];
	dic								= [defaults dictionaryForKey:NET_BROADCAST];
	_broadcastHostList				= [[NSMutableArray alloc] initWithArray:[dic objectForKey:@"Host"]];
	_broadcastIPList				= [[NSMutableArray alloc] initWithArray:[dic objectForKey:@"IPAddress"]];
	_broadcastAddresses				= nil;
	[self updateBroadcastAddresses];
	// 送信
	self.quoteString				= [defaults stringForKey:SEND_QUOT_STR];
	self.openNewOnDockClick			= [defaults boolForKey:SEND_DOCK_SEND];
	self.sealCheckDefault			= [defaults boolForKey:SEND_SEAL_CHECK];
	self.hideReceiveWindowOnReply	= [defaults boolForKey:SEND_HIDE_REPLY];
	self.noticeSealOpened			= [defaults boolForKey:SEND_OPENSEAL_CHECK];
	self.allowSendingToMultiUser	= [defaults boolForKey:SEND_MULTI_USER_CHECK];
	str								= [defaults stringForKey:SEND_MSG_FONT_NAME];
	fVal							= [defaults floatForKey:SEND_MSG_FONT_SIZE];
	if (str && (fVal > 0)) {
		self.sendMessageFont		= [NSFont fontWithName:str size:fVal];
	}
	// 受信
	self.receiveSoundName			= [defaults stringForKey:RECV_SOUND];
	self.quoteCheckDefault			= [defaults boolForKey:RECV_QUOT_CHECK];
	self.nonPopup					= [defaults boolForKey:RECV_NON_POPUP];
	self.nonPopupWhenAbsence		= [defaults boolForKey:RECV_ABSENCE_NONPOPUP];
	self.iconBoundModeInNonPopup	= [defaults integerForKey:RECV_BOUND_IN_NONPOPUP];
	self.useClickableURL			= [defaults boolForKey:RECV_CLICKABLE_URL];
	str								= [defaults stringForKey:RECV_MSG_FONT_NAME];
	fVal							= [defaults floatForKey:RECV_MSG_FONT_SIZE];
	if (str && (fVal > 0)) {
		self.receiveMessageFont		= [NSFont fontWithName:str size:fVal];
	}
	// 不在
	array							= [defaults arrayForKey:ABSENCE];
	if (!array) {
		array						= _defaultAbsences;
	}
	_absenceList					= [[NSMutableArray alloc] initWithArray:array];
	self.absenceIndex				= -1;
	// 通知拒否
	array							= [defaults arrayForKey:REFUSE];
	_refuseList						= [[self convertRefuseDefaultsToInfo:array] retain];
	// ログ
	self.standardLogEnabled			= [defaults boolForKey:LOG_STD_ON];
	self.logChainedWhenOpen			= [defaults boolForKey:LOG_STD_CHAIN];
	self.standardLogFile			= [defaults stringForKey:LOG_STD_FILE];
	self.alternateLogEnabled		= [defaults boolForKey:LOG_ALT_ON];
	self.logWithSelectedRange		= [defaults boolForKey:LOG_ALT_SELECTION];
	self.alternateLogFile			= [defaults stringForKey:LOG_ALT_FILE];

	// 送受信ウィンドウ
	size.width						= [defaults floatForKey:SNDWIN_SIZE_W];
	size.height						= [defaults floatForKey:SNDWIN_SIZE_H];
	self.sendWindowSize				= size;
	self.sendWindowSplit			= [defaults floatForKey:SNDWIN_SIZE_SPLIT];
	self.sendSearchByUserName		= [defaults boolForKey:SNDSEARCH_USER];
	self.sendSearchByGroupName		= [defaults boolForKey:SNDSEARCH_GROUP];
	self.sendSearchByHostName		= [defaults boolForKey:SNDSEARCH_HOST];
	self.sendSearchByLogOnName		= [defaults boolForKey:SNDSEARCH_LOGON];
	_sendUserListColDisp			= [[NSMutableDictionary alloc] init];
	dic								= [defaults dictionaryForKey:SNDWIN_USERLIST_COL];
	if (dic) {
		[_sendUserListColDisp setDictionary:dic];
	}
	size.width						= [defaults floatForKey:RCVWIN_SIZE_W];
	size.height						= [defaults floatForKey:RCVWIN_SIZE_H];
	self.receiveWindowSize			= size;
	#if IPMSG_LOG_DBG
		// デバッグ用ログ出力
		NSUInteger	count;

		objc_property_t* props = class_copyPropertyList([self class], &count);
		DBG(@"properties[%u]=(", count);
		for (i = 0; i < count; i++) {
			const char*	name;
			id			val;
			name	= property_getName(props[i]);
			val		= [self valueForKey:[NSString stringWithUTF8String:name]];
			array	= [[val description] componentsSeparatedByString:@"\n"];
			if ([array count] > 1) {
				NSUInteger num = 0;
				for (NSString* s in array) {
					num++;
					if (num == 1) {
						DBG(@"\t%s=%@", name, s);
					} else if (num == [array count]) {
						DBG(@"\t\t%@;", s);
					} else {
						DBG(@"\t\t%@", s);
					}
				}
			} else if ([val isKindOfClass:[NSString class]]) {
				DBG(@"\t%s=\"%@\";", name, val);
			} else {
				DBG(@"\t%s=%@;", name, val);
			}
		}
		free(props);
		DBG(@")");

		Ivar* ivars = class_copyIvarList([self class], &count);
		TRC(@"ivars[%u]=(", count);
		for (i = 0; i < count; i++) {
			const char*	name;
			id			val;
			name	= ivar_getName(ivars[i]);
			val		= [self valueForKey:[NSString stringWithUTF8String:name]];
			if ((strcmp(name, "_absenceList") == 0) ||
				(strcmp(name, "_defaultAbsences") == 0)) {
				TRC(@"\t%s=(", name);
				for (dic in val) {
					NSString* t = [dic objectForKey:@"Title"];
					NSString* m = [dic objectForKey:@"Message"];
					str = [m stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
					TRC(@"\t\t\"%@\"（\"%@\"）", t, str);
				}
				TRC(@"\t);");
			} else {
				array	= [[val description] componentsSeparatedByString:@"\n"];
				if ([array count] > 1) {
					NSUInteger num = 0;
					for (NSString* s in array) {
						num++;
						if (num == 1) {
							TRC(@"\t%s=%@", name, s);
						} else if (num == [array count]) {
							TRC(@"\t%@;", s);
						} else {
							TRC(@"\t%@", s);
						}
					}
				} else if ([val isKindOfClass:[NSString class]]) {
					TRC(@"\t%s=\"%@\";", name, val);
				} else {
					TRC(@"\t%s=%@;", name, val);
				}
			}
		}
		free(ivars);
		TRC(@")");
	#endif

	DBG(@"======== Init Config complated ========");

	return self;
}

// 解放
- (void)dealloc
{
	[_userName release];
	[_groupName release];
	[_password release];
	[_quoteString release];
	[_absenceList release];
	[_refuseList release];
	[_sendMessageFont release];
	[_sendUserListColDisp release];
	[_receiveSound release];
	[_receiveMessageFont release];
	[_standardLogFile release];
	[_alternateLogFile release];
	[_defaultMessageFont release];
	[_defaultAbsences release];

	[_broadcastHostList release];
	[_broadcastIPList release];
	[_broadcastAddresses release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * 永続化
 *----------------------------------------------------------------------------*/
- (void)save
{
	NSUserDefaults*	def		= [NSUserDefaults standardUserDefaults];
	NSBundle*		mb		= [NSBundle mainBundle];
	NSString*		ver		= [mb objectForInfoDictionaryKey:@"CFBundleVersion"];
	NSString*		verstr	= [mb objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSDictionary*	dic		= [NSDictionary dictionaryWithObjectsAndKeys:
													_broadcastHostList, @"Host",
													_broadcastIPList, @"IPAddress",
													nil];

	// 全般
	[def setObject:ver forKey:GEN_VERSION];
	[def setObject:verstr forKey:GEN_VERSION_STR];
	[def setObject:self.userName forKey:GEN_USER_NAME];
	[def setObject:self.groupName forKey:GEN_GROUP_NAME];
	[def setObject:self.password forKey:GEN_PASSWORD];
	[def setBool:self.useStatusBar forKey:GEN_USE_STATUS_BAR];

	// ネットワーク
	[def setInteger:self.portNo forKey:NET_PORT_NO];
	[def setBool:self.dialup forKey:NET_DIALUP];
	[def setObject:dic forKey:NET_BROADCAST];

	// 送信
	[def setObject:self.quoteString forKey:SEND_QUOT_STR];
	[def setBool:self.openNewOnDockClick forKey:SEND_DOCK_SEND];
	[def setBool:self.sealCheckDefault forKey:SEND_SEAL_CHECK];
	[def setBool:self.hideReceiveWindowOnReply forKey:SEND_HIDE_REPLY];
	[def setBool:self.noticeSealOpened forKey:SEND_OPENSEAL_CHECK];
	[def setBool:self.allowSendingToMultiUser forKey:SEND_MULTI_USER_CHECK];
	if (self.sendMessageFont) {
		[def setObject:[self.sendMessageFont fontName] forKey:SEND_MSG_FONT_NAME];
		[def setFloat:[self.sendMessageFont pointSize] forKey:SEND_MSG_FONT_SIZE];
	}
	// 受信
	[def setObject:[self.receiveSound name] forKey:RECV_SOUND];
	[def setBool:self.quoteCheckDefault forKey:RECV_QUOT_CHECK];
	[def setBool:self.nonPopup forKey:RECV_NON_POPUP];
	[def setBool:self.nonPopupWhenAbsence forKey:RECV_ABSENCE_NONPOPUP];
	[def setInteger:self.iconBoundModeInNonPopup forKey:RECV_BOUND_IN_NONPOPUP];
	[def setBool:self.useClickableURL forKey:RECV_CLICKABLE_URL];
	if (self.receiveMessageFont) {
		[def setObject:[self.receiveMessageFont fontName] forKey:RECV_MSG_FONT_NAME];
		[def setFloat:[self.receiveMessageFont pointSize] forKey:RECV_MSG_FONT_SIZE];
	}

	// 不在
	[def setObject:_absenceList forKey:ABSENCE];
	// 通知拒否
	[def setObject:[self convertRefuseInfoToDefaults:_refuseList] forKey:REFUSE];
	// ログ
	[def setBool:self.standardLogEnabled forKey:LOG_STD_ON];
	[def setBool:self.logChainedWhenOpen forKey:LOG_STD_CHAIN];
	[def setObject:self.standardLogFile forKey:LOG_STD_FILE];
	[def setBool:self.alternateLogEnabled forKey:LOG_ALT_ON];
	[def setBool:self.logWithSelectedRange forKey:LOG_ALT_SELECTION];
	[def setObject:self.alternateLogFile forKey:LOG_ALT_FILE];

	// 送受信ウィンドウ位置／サイズ
	[def setFloat:self.sendWindowSize.width forKey:SNDWIN_SIZE_W];
	[def setFloat:self.sendWindowSize.height forKey:SNDWIN_SIZE_H];
	[def setFloat:self.sendWindowSplit forKey:SNDWIN_SIZE_SPLIT];
	[def setBool:self.sendSearchByUserName forKey:SNDSEARCH_USER];
	[def setBool:self.sendSearchByGroupName forKey:SNDSEARCH_GROUP];
	[def setBool:self.sendSearchByHostName forKey:SNDSEARCH_HOST];
	[def setBool:self.sendSearchByLogOnName forKey:SNDSEARCH_LOGON];
	[def setObject:_sendUserListColDisp forKey:SNDWIN_USERLIST_COL];
	[def setFloat:self.receiveWindowSize.width forKey:RCVWIN_SIZE_W];
	[def setFloat:self.receiveWindowSize.height forKey:RCVWIN_SIZE_H];

	// 保存
	[def synchronize];
}

/*----------------------------------------------------------------------------*
 * 「ネットワーク」関連
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark ネットワーク関連

// ブロードキャスト
- (NSUInteger)numberOfBroadcasts
{
	return [_broadcastHostList count] + [_broadcastIPList count];
}

- (NSString*)broadcastAtIndex:(NSUInteger)index
{
	@try {
		NSUInteger hostnum = [_broadcastHostList count];
		if (index < hostnum) {
			return [_broadcastHostList objectAtIndex:index];
		}
		return [_broadcastIPList objectAtIndex:index - hostnum];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
	return nil;
}

- (BOOL)containsBroadcastWithAddress:(NSString*)address
{
	return [_broadcastIPList containsObject:address];
}

- (BOOL)containsBroadcastWithHost:(NSString*)host
{
	return [_broadcastHostList containsObject:host];
}

- (void)addBroadcastWithAddress:(NSString*)address
{
	@try {
		[_broadcastIPList addObject:address];
		[_broadcastIPList sortUsingSelector:@selector(compare:)];
		[self updateBroadcastAddresses];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%@)", exception, address);
	}
}

- (void)addBroadcastWithHost:(NSString*)host
{
	@try {
		[_broadcastHostList addObject:host];
		[_broadcastHostList sortUsingSelector:@selector(compare:)];
		[self updateBroadcastAddresses];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%@)", exception, host);
	}
}

- (void)removeBroadcastAtIndex:(NSUInteger)index
{
	@try {
		int hostnum = [_broadcastHostList count];
		if (index < hostnum) {
			[_broadcastHostList removeObjectAtIndex:index];
		} else {
			[_broadcastIPList removeObjectAtIndex:index - hostnum];
		}
		[self updateBroadcastAddresses];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

/*----------------------------------------------------------------------------*
 * 「アップデート」関連
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark アップデート関連

- (BOOL)updateAutomaticCheck
{
	return [[SUUpdater sharedUpdater] automaticallyChecksForUpdates];
}

- (void)setUpdateAutomaticCheck:(BOOL)b
{
	[[SUUpdater sharedUpdater] setAutomaticallyChecksForUpdates:b];
}

- (NSTimeInterval)updateCheckInterval
{
	return [[SUUpdater sharedUpdater] updateCheckInterval];
}

- (void)setUpdateCheckInterval:(NSTimeInterval)interval
{
	[[SUUpdater sharedUpdater] setUpdateCheckInterval:interval];
}

/*----------------------------------------------------------------------------*
 * 「送信」関連
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark 送信関連

// メッセージ部フォント
- (NSFont*)defaultSendMessageFont
{
	return _defaultMessageFont;
}

- (NSFont*)sendMessageFont
{
	return (_sendMessageFont) ? _sendMessageFont : _defaultMessageFont;
}

- (void)setSendMessageFont:(NSFont*)font
{
	[font retain];
	[_sendMessageFont release];
	_sendMessageFont = font;
}

// ユーザリスト表示項目
- (BOOL)sendWindowUserListColumnHidden:(id)identifier
{
	NSNumber* val = [_sendUserListColDisp objectForKey:identifier];
	if (val) {
		return ![val boolValue];
	}
	return NO;
}

- (void)setSendWindowUserListColumn:(id)identifier hidden:(BOOL)hidden
{
	[_sendUserListColDisp setObject:[NSNumber numberWithBool:!hidden] forKey:identifier];
}

/*----------------------------------------------------------------------------*
 * 「受信」関連
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark 受信関連

// 受信音
- (NSString*)receiveSoundName
{
	return [_receiveSound name];
}

- (void)setReceiveSoundName:(NSString*)soundName
{
	[_receiveSound autorelease];
	_receiveSound = nil;
	if (soundName) {
		if ([soundName length] > 0) {
			_receiveSound = [[NSSound soundNamed:soundName] retain];
		}
	}
}

// メッセージ部フォント
- (NSFont*)defaultReceiveMessageFont
{
	return _defaultMessageFont;
}

- (NSFont*)receiveMessageFont
{
	return (_receiveMessageFont) ? _receiveMessageFont : _defaultMessageFont;
}

- (void)setReceiveMessageFont:(NSFont*)font
{
	[font retain];
	[_receiveMessageFont release];
	_receiveMessageFont = font;
}

/*----------------------------------------------------------------------------*
 * 「不在」関連
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark 不在関連

- (NSUInteger)numberOfAbsences
{
	return [_absenceList count];
}

- (NSString*)absenceTitleAtIndex:(NSUInteger)index
{
	@try {
		return [[_absenceList objectAtIndex:index] objectForKey:@"Title"];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
	return nil;
}

- (NSString*)absenceMessageAtIndex:(NSUInteger)index
{
	@try {
		return [[_absenceList objectAtIndex:index] objectForKey:@"Message"];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
	return nil;
}

- (BOOL)containsAbsenceTitle:(NSString*)title
{
	@try {
		for (NSDictionary* dic in _absenceList) {
			if ([title isEqualToString:[dic objectForKey:@"Title"]]) {
				return YES;
			}
		}
	} @catch (NSException* exception) {
		ERR(@"%@(index=%@)", exception, title);
	}
	return NO;
}

- (void)addAbsenceTitle:(NSString*)title message:(NSString*)msg
{
	@try {
		NSMutableDictionary* dic = [NSMutableDictionary dictionary];
		[dic setObject:title forKey:@"Title"];
		[dic setObject:msg forKey:@"Message"];
		[_absenceList addObject:dic];
	} @catch (NSException* exception) {
		ERR(@"%@(title=%@,msg=%@)", exception, title, msg);
	}
}

- (void)insertAbsenceTitle:(NSString*)title message:(NSString*)msg atIndex:(NSUInteger)index
{
	@try {
		NSMutableDictionary* dic = [NSMutableDictionary dictionary];
		[dic setObject:title forKey:@"Title"];
		[dic setObject:msg forKey:@"Message"];
		[_absenceList insertObject:dic atIndex:index];
	} @catch (NSException* exception) {
		ERR(@"%@(title=%@,msg=%@,index=%u)", exception, title, msg, index);
	}
}

- (void)setAbsenceTitle:(NSString*)title message:(NSString*)msg atIndex:(NSInteger)index
{
	@try {
		NSMutableDictionary* dic = [NSMutableDictionary dictionary];
		[dic setObject:title forKey:@"Title"];
		[dic setObject:msg forKey:@"Message"];
		[_absenceList replaceObjectAtIndex:index withObject:dic];
	} @catch (NSException* exception) {
		ERR(@"%@(title=%@,msg=%@,index=%u)", exception, title, msg, index);
	}
}

- (void)upAbsenceAtIndex:(NSUInteger)index
{
	@try {
		id obj = [[_absenceList objectAtIndex:index] retain];
		[_absenceList removeObjectAtIndex:index];
		[_absenceList insertObject:obj atIndex:index - 1];
		[obj release];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

- (void)downAbsenceAtIndex:(NSUInteger)index
{
	@try {
		id obj = [[_absenceList objectAtIndex:index] retain];
		[_absenceList removeObjectAtIndex:index];
		[_absenceList insertObject:obj atIndex:index + 1];
		[obj release];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

- (void)removeAbsenceAtIndex:(NSUInteger)index
{
	@try {
		[_absenceList removeObjectAtIndex:index];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

- (void)resetAllAbsences
{
	[_absenceList removeAllObjects];
	[_absenceList addObjectsFromArray:_defaultAbsences];
}

- (BOOL)inAbsence
{
	return (_absenceIndex >= 0);
}

- (NSInteger)absenceIndex
{
	return _absenceIndex;
}

- (void)setAbsenceIndex:(NSInteger)index
{
	if ((index >= 0) && (index < [_absenceList count])) {
		_absenceIndex = index;
	} else {
		_absenceIndex = -1;
	}
}

/*----------------------------------------------------------------------------*
 * 「通知拒否」関連
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark 通知拒否関連

- (NSUInteger)numberOfRefuseInfo
{
	return [_refuseList count];
}

- (RefuseInfo*)refuseInfoAtIndex:(NSUInteger)index
{
	@try {
		return [_refuseList objectAtIndex:index];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
	return nil;
}

- (void)addRefuseInfo:(RefuseInfo*)info
{
	@try {
		[_refuseList addObject:info];
	} @catch (NSException* exception) {
		ERR(@"%@(info=%@)", exception, info);
	}
}

- (void)insertRefuseInfo:(RefuseInfo*)info atIndex:(NSUInteger)index
{
	@try {
		[_refuseList insertObject:info atIndex:index];
	} @catch (NSException* exception) {
		ERR(@"%@(info=%@,index=%u)", exception, info, index);
	}
}

- (void)setRefuseInfo:(RefuseInfo*)info atIndex:(NSUInteger)index
{
	@try {
		[_refuseList replaceObjectAtIndex:index withObject:info];
	} @catch (NSException* exception) {
		ERR(@"%@(info=%@,index=%u)", exception, info, index);
	}
}

- (void)upRefuseInfoAtIndex:(NSUInteger)index
{
	@try {
		id obj = [[_refuseList objectAtIndex:index] retain];
		[_refuseList removeObjectAtIndex:index];
		[_refuseList insertObject:obj atIndex:index - 1];
		[obj release];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

- (void)downRefuseInfoAtIndex:(NSUInteger)index
{
	@try {
		id obj = [[_refuseList objectAtIndex:index] retain];
		[_refuseList removeObjectAtIndex:index];
		[_refuseList insertObject:obj atIndex:index + 1];
		[obj release];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

- (void)removeRefuseInfoAtIndex:(NSUInteger)index
{
	@try {
		[_refuseList removeObjectAtIndex:index];
	} @catch (NSException* exception) {
		ERR(@"%@(index=%u)", exception, index);
	}
}

- (BOOL)matchRefuseCondition:(UserInfo*)user
{
	for (RefuseInfo* info in _refuseList) {
		if ([info match:user]) {
			return YES;
		}
	}
	return NO;
}

/*----------------------------------------------------------------------------*
 * 内部利用
 *----------------------------------------------------------------------------*/
#pragma mark -
#pragma mark 内部利用

// ブロードキャスト対象アドレスリスト更新
- (void)updateBroadcastAddresses
{
	NSMutableArray* newList = [NSMutableArray array];
	for (NSString* host in _broadcastHostList) {
		NSString* addr = [[NSHost hostWithName:host] address];
		if (addr) {
			if (![newList containsObject:addr]) {
				[newList addObject:addr];
			}
		}
	}
	for (NSString* addr in _broadcastIPList) {
		if (![newList containsObject:addr]) {
			[newList addObject:addr];
		}
	}
	self.broadcastAddresses = newList;
}

// 通知拒否リスト変換
- (NSMutableArray*)convertRefuseDefaultsToInfo:(NSArray*)array
{
	NSMutableArray* newArray = [NSMutableArray array];
	for (NSDictionary* dic in array) {
		IPRefuseTarget		target			= 0;
		NSString*			targetStr		= [dic objectForKey:@"Target"];
		NSString*			string			= [dic objectForKey:@"String"];
		IPRefuseCondition	condition		= 0;
		NSString*			conditionStr	= [dic objectForKey:@"Condition"];
		if (!targetStr || !string || !conditionStr) {
			continue;
		}
		if ([targetStr isEqualToString:@"UserName"]) {			target = IP_REFUSE_USER;	}
		else if ([targetStr isEqualToString:@"GroupName"]) {	target = IP_REFUSE_GROUP;	}
		else if ([targetStr isEqualToString:@"MachineName"]) {	target = IP_REFUSE_MACHINE;	}
		else if ([targetStr isEqualToString:@"LogOnName"]) {	target = IP_REFUSE_LOGON;	}
		else if ([targetStr isEqualToString:@"IPAddress"]) {	target = IP_REFUSE_ADDRESS;	}
		else {
			WRN(@"invalid refuse target(%@)", targetStr);
			continue;
		}
		if ([string length] <= 0) {
			continue;
		}
		if ([conditionStr isEqualToString:@"Match"]) {			condition = IP_REFUSE_MATCH;	}
		else if ([conditionStr isEqualToString:@"Contain"]) {	condition = IP_REFUSE_CONTAIN;	}
		else if ([conditionStr isEqualToString:@"Start"]) {		condition = IP_REFUSE_START;	}
		else if ([conditionStr isEqualToString:@"End"]) {		condition = IP_REFUSE_END;		}
		else {
			WRN(@"invalid refuse condition(%@)", conditionStr);
			continue;
		}

		[newArray addObject:[RefuseInfo refuseInfoWithTarget:target
													  string:string
												   condition:condition]];
	}
	return newArray;
}

- (NSMutableArray*)convertRefuseInfoToDefaults:(NSArray*)array
{
	NSMutableArray* newArray = [NSMutableArray array];
	for (RefuseInfo* info in array) {
		NSMutableDictionary*	dict		= [NSMutableDictionary dictionary];
		NSString*				target		= nil;
		NSString*				condition	= nil;
		switch ([info target]) {
			case IP_REFUSE_USER:	target = @"UserName";		break;
			case IP_REFUSE_GROUP:	target = @"GroupName";		break;
			case IP_REFUSE_MACHINE:	target = @"MachineName";	break;
			case IP_REFUSE_LOGON:	target = @"LogOnName";		break;
			case IP_REFUSE_ADDRESS:	target = @"IPAddress";		break;
			default:
				WRN(@"invalid refuse target(%d)", [info target]);
				continue;
		}
		switch ([info condition]) {
			case IP_REFUSE_MATCH:	condition = @"Match";		break;
			case IP_REFUSE_CONTAIN:	condition = @"Contain";		break;
			case IP_REFUSE_START:	condition = @"Start";		break;
			case IP_REFUSE_END:		condition = @"End";			break;
			default:
				WRN(@"invalid refuse condition(%d)", [info condition]);
				continue;
		}
		[dict setObject:target forKey:@"Target"];
		[dict setObject:[info string] forKey:@"String"];
		[dict setObject:condition forKey:@"Condition"];
		[newArray addObject:dict];
	}
	return newArray;
}

@end
