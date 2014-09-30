/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: MessageCenter.m
 *	Module		: メッセージ送受信管理クラス
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import <SystemConfiguration/SCDynamicStoreKey.h>
#import <SystemConfiguration/SCSchemaDefinitions.h>

#import "IPMessenger.h"
#import "MessageCenter.h"
#import "AppControl.h"
#import "Config.h"
#import "PortChangeControl.h"
#import "UserManager.h"
#import "UserInfo.h"
#import "RecvMessage.h"
#import "SendMessage.h"
#import "RetryInfo.h"
#import "NoticeControl.h"
#import "AttachmentServer.h"
#import "Attachment.h"
#import "AttachmentFile.h"
#import "NSStringIPMessenger.h"
#import	"DebugLog.h"

// UNIXソケット関連
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

/*============================================================================*
 * 定数定義
 *============================================================================*/

#define RETRY_INTERVAL	(2.0)
#define RETRY_MAX		(3)

typedef enum
{
	_NET_NO_CHANGE_IN_LINK,
	_NET_NO_CHANGE_IN_UNLINK,
	_NET_LINK_GAINED,
	_NET_LINK_LOST,
	_NET_PRIMARY_IF_CHANGED,
	_NET_IP_ADDRESS_CHANGED

} _NetUpdateState;

/*============================================================================*
 * プライベートメソッド
 *============================================================================*/

@interface MessageCenter()
- (NSData*)entryMessageData;
- (void)shutdownServer;
- (void)serverThread:(NSArray*)portArray;
- (BOOL)updateHostName;
- (_NetUpdateState)updateIPAddress;
- (_NetUpdateState)updatePrimaryNIC;
- (void)systemConfigurationUpdated:(NSArray*)changedKeys;
@end

/*============================================================================*
 * ローカル関数
 *============================================================================*/

// DynamicStore Callback Func
static void _DynamicStoreCallback(SCDynamicStoreRef	store,
								  CFArrayRef		changedKeys,
								  void*				info);

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation MessageCenter

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

// 共有インスタンスを返す
+ (MessageCenter*)sharedCenter
{
	static MessageCenter* sharedCenter = nil;
	if (!sharedCenter) {
		sharedCenter = [[MessageCenter alloc] init];
	}
	return sharedCenter;
}

// 次のメッセージIDを返す
+ (long)nextMessageID {
	static long messageID = 0;
	return ++messageID;
}

// ネットワークに接続しているかを返す
+ (BOOL)isNetworkLinked {
	MessageCenter* me = [MessageCenter sharedCenter];
	if (me) {
		return (BOOL)(me->myIPAddress != 0);
	}
	return NO;
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)init
{
	Config*				config	= [Config sharedConfig];
	NSArray*			keys	= nil;
	int					sockopt	= 1;
	struct sockaddr_in	addr;

	self				= [super init];
	sockUDP				= -1;
	sockLock			= [[NSLock alloc] init];
	sendList			= [[NSMutableDictionary alloc] init];
	serverConnection	= nil;
	serverLock			= [[NSLock alloc] init];
	serverShutdown		= FALSE;
	runLoopSource		= nil;
	scDynStore			= nil;
	scKeyHostName		= nil;
	scKeyNetIPv4		= nil;
	scKeyIFIPv4			= nil;
	primaryNIC			= nil;
	myIPAddress			= 0;
	myPortNo			= config.portNo;
	myHostName			= nil;
	memset(&scDSContext, 0, sizeof(scDSContext));

	if (myPortNo <= 0) {
		myPortNo = IPMSG_DEFAULT_PORT;
	}

	// DynaimcStore生成
	scDSContext.info	= self;
	scDynStore	= SCDynamicStoreCreate(NULL,
								   (CFStringRef)@"net.ishwt.IPMessenger",
								   _DynamicStoreCallback,
								   &scDSContext);
	if (!scDynStore) {
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSRunCriticalAlertPanel(NSLocalizedString(@"Err.DynStoreCreate..title", nil),
								NSLocalizedString(@"Err.DynStoreCreate.msg", nil),
								@"OK", nil, nil);
		// プログラム終了
		[NSApp terminate:self];
		[self autorelease];
		return nil;
	}

	// DynamicStore更新通知設定
	scKeyHostName	= (NSString*)SCDynamicStoreKeyCreateHostNames(NULL);
	scKeyNetIPv4	= (NSString*)SCDynamicStoreKeyCreateNetworkGlobalEntity(
								NULL, kSCDynamicStoreDomainState, kSCEntNetIPv4);
	keys = [NSArray arrayWithObjects:scKeyHostName, scKeyNetIPv4, nil];

	if (!SCDynamicStoreSetNotificationKeys(scDynStore, (CFArrayRef)keys, NULL)) {
		ERR(@"dynamic store notification set error");
	}
	runLoopSource = SCDynamicStoreCreateRunLoopSource(NULL, scDynStore, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);

	// DynamicStoreからの情報取得
	[self updateHostName];
	[self updateIPAddress];
	if (myIPAddress == 0) {
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSRunCriticalAlertPanel(NSLocalizedString(@"Err.NetCheck.title", nil),
								NSLocalizedString(@"Err.NetCheck.msg", nil),
								@"OK", nil, nil);
	}

	// 乱数初期化
	srand(time(NULL));

	// ソケットオープン
	if ((sockUDP = socket(AF_INET, SOCK_DGRAM, 0)) == -1) {
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSRunCriticalAlertPanel(NSLocalizedString(@"Err.UDPSocketOpen.title", nil),
								NSLocalizedString(@"Err.UDPSocketOpen.msg", nil),
								@"OK", nil, nil);
		// プログラム終了
		[NSApp terminate:self];
		[self autorelease];
		return nil;
	}

	// ソケットバインドアドレスの用意
	memset(&addr, 0, sizeof(addr));
	addr.sin_family			= AF_INET;
	addr.sin_addr.s_addr	= htonl(INADDR_ANY);
	addr.sin_port			= htons(myPortNo);

	// ソケットバインド
	while (bind(sockUDP, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
		int result;
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		result = NSRunCriticalAlertPanel(
							NSLocalizedString(@"Err.UDPSocketBind.title", nil),
							NSLocalizedString(@"Err.UDPSocketBind.msg", nil),
							NSLocalizedString(@"Err.UDPSocketBind.ok", nil),
							nil,
							NSLocalizedString(@"Err.UDPSocketBind.alt", nil),
							myPortNo);
		if (result == NSOKButton) {
			// プログラム終了
			[NSApp terminate:self];
			[self autorelease];
			return nil;
		}
		[[[PortChangeControl alloc] init] autorelease];
		myPortNo		= config.portNo;
		addr.sin_port	= htons(myPortNo);
	}

	// ブロードキャスト許可設定
	sockopt = 1;
	setsockopt(sockUDP, SOL_SOCKET, SO_BROADCAST, &sockopt, sizeof(sockopt));
	// バッファサイズ設定
	sockopt = MAX_SOCKBUF;
	setsockopt(sockUDP, SOL_SOCKET, SO_SNDBUF, &sockopt, sizeof(sockopt));
	setsockopt(sockUDP, SOL_SOCKET, SO_RCVBUF, &sockopt, sizeof(sockopt));

	// 受信スレッド起動
	{
		NSPort*		port1	= [NSPort port];
		NSPort*		port2	= [NSPort port];
		NSArray*	array	= [NSArray arrayWithObjects:port2, port1, nil];
		serverConnection	= [[NSConnection alloc] initWithReceivePort:port1 sendPort:port2];
		[serverConnection setRootObject:self];
		[NSThread detachNewThreadSelector:@selector(serverThread:) toTarget:self withObject:array];
	}

	return self;
}

// 解放
-(void)dealloc
{
	[sockLock release];
	[sendList release];
	[serverConnection release];
	[serverLock release];
	if (sockUDP != -1) {
		close(sockUDP);
	}
	if (runLoopSource) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
		CFRelease(runLoopSource);
	}
	[scKeyHostName release];
	[scKeyNetIPv4 release];
	[scKeyIFIPv4 release];
	if (scDynStore) {
		CFRelease(scDynStore);
	}
	[myHostName release];
	[primaryNIC release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * プライベート使用
 *----------------------------------------------------------------------------*/

// データ送信実処理
- (NSInteger)sendTo:(struct sockaddr_in*)toAddr messageID:(NSInteger)mid command:(UInt32)cmd data:(NSData*)data
{
	Config*	config = [Config sharedConfig];

	// 不在モードチェック
	if (config.inAbsence) {
		cmd |= IPMSG_ABSENCEOPT;
	}
	// ダイアルアップチェック
	if (config.dialup) {
		cmd |= IPMSG_DIALUPOPT;
	}

	[sockLock lock];	// ソケットロック

	// メッセージID採番
	if (mid < 0) {
		mid = [MessageCenter nextMessageID];
	}

	// メッセージヘッダ部編集
	NSString*	header	= [NSString stringWithFormat:@"%d:%ld:%@:%@:%ld:",
								IPMSG_VERSION, (long)mid, NSUserName(), myHostName, cmd];
	const char*	str		= [header SJISString];
	NSUInteger	len		= strlen(str);

	// 送信データ作成
	NSMutableData* sendData = [NSMutableData dataWithCapacity:len + [data length]];
	[sendData appendBytes:str length:len];
	if ([data length] > 0) {
		[sendData appendData:data];
	}

	// パケットサイズあふれ調整
	len = [sendData length];
	if (len > MAX_SOCKBUF) {
		len = MAX_SOCKBUF;
	}
	// 送信
	sendto(sockUDP, [sendData bytes], len, 0, (struct sockaddr*)toAddr, sizeof(struct sockaddr_in));

	[sockLock unlock];	// ロック解除

	return mid;
}

- (NSInteger)sendTo:(UserInfo*)toUser messageID:(NSInteger)mid command:(UInt32)cmd message:(NSString*)msg option:(NSString*)opt
{
	struct sockaddr_in	addr		= toUser.address;
	NSData*				sendData	= nil;

	if (msg || opt) {
		const char*	str1 = (toUser.supportsUTF8) ? [msg UTF8String] : [msg SJISString];
		NSUInteger	len1 = strlen(str1);
		if (opt) {
			const char*		str2 = (toUser.supportsUTF8) ? [opt UTF8String] : [opt SJISString];
			NSUInteger		len2 = strlen(str2);
			NSMutableData*	data = [NSMutableData dataWithCapacity:len1 + 1 + len2 + 1];
			[data appendBytes:str1 length:len1 + 1];
			[data appendBytes:str2 length:len2 + 1];
			sendData = data;
		} else {
			sendData = [NSData dataWithBytes:str1 length:len1 + 1];
		}
		if (toUser.supportsUTF8) {
			cmd |= IPMSG_UTF8OPT;
		}
	}

	return [self sendTo:&addr
			  messageID:mid
				command:cmd
				   data:sendData];
}

- (NSInteger)sendTo:(UserInfo*)toUser messageID:(NSInteger)mid command:(UInt32)cmd number:(NSInteger)num
{
	return [self sendTo:toUser
			  messageID:mid
				command:cmd
				message:[NSString stringWithFormat:@"%d", num]
				 option:nil];
}

/*----------------------------------------------------------------------------*
 * メッセージ送信（ブロードキャスト）
 *----------------------------------------------------------------------------*/

// ブロードキャスト送信処理
- (void)sendBroadcast:(UInt32)cmd data:(NSData*)data
{
	// ブロードキャスト（ローカル）アドレスへ送信
	struct sockaddr_in	bcast;
	memset(&bcast, 0, sizeof(bcast));
	bcast.sin_family		= AF_INET;
	bcast.sin_port			= htons(myPortNo);
	bcast.sin_addr.s_addr	= htonl(INADDR_BROADCAST);
	[self sendTo:&bcast messageID:-1 command:cmd data:data];

	// 個別ブロードキャストへ送信
	NSMutableSet* castSet = [NSMutableSet set];
	[castSet addObjectsFromArray:[[Config sharedConfig] broadcastAddresses]];
	[castSet addObjectsFromArray:[[UserManager sharedManager] dialupAddresses]];
	for (NSString* address in castSet) {
		bcast.sin_addr.s_addr = inet_addr([address UTF8String]);
		if (bcast.sin_addr.s_addr != INADDR_NONE) {
			[self sendTo:&bcast messageID:-1 command:cmd data:data];
		}
	}
}

// BR_ENTRYのブロードキャスト
- (void)broadcastEntry
{
	[self sendBroadcast:IPMSG_NOOPERATION data:nil];
	[self sendBroadcast:IPMSG_BR_ENTRY|IPMSG_FILEATTACHOPT|IPMSG_CAPUTF8OPT
				   data:[self entryMessageData]];
	DBG(@"broadcast entry");
}

// BR_ABSENCEのブロードキャスト
- (void)broadcastAbsence
{
	[self sendBroadcast:IPMSG_BR_ABSENCE|IPMSG_FILEATTACHOPT|IPMSG_CAPUTF8OPT
				   data:[self entryMessageData]];
	DBG(@"broadcast absence");
}

// BR_EXITをブロードキャスト
- (void)broadcastExit
{
	[self sendBroadcast:IPMSG_BR_EXIT|IPMSG_CAPUTF8OPT
				   data:[self entryMessageData]];
	DBG(@"broadcast exit");
}

/*----------------------------------------------------------------------------*
 * メッセージ送信（通常）
 *----------------------------------------------------------------------------*/

// 通常メッセージの送信
- (void)sendMessage:(SendMessage*)msg to:(NSArray*)toUsers
{
	AttachmentServer*	attachManager	= [AttachmentServer sharedServer];
	UInt32				command			= IPMSG_SENDMSG | IPMSG_SENDCHECKOPT;
	NSString*			option			= nil;

	// コマンドの決定
	if ([toUsers count] > 1) {
		command |= IPMSG_MULTICASTOPT;
	}
	if (msg.sealed) {
		command |= IPMSG_SECRETOPT;
		if (msg.locked) {
			command |= IPMSG_PASSWORDOPT;
		}
	}

	// 添付ファイルメッセージ編集
	if ([msg.attachments count] > 0) {
		NSInteger			count			= 0;
		NSMutableString*	buffer			= [NSMutableString string];
		NSNumber*			messageID		= [NSNumber numberWithInt:msg.packetNo];
		for (Attachment* info in msg.attachments) {
			info.fileID	= [NSNumber numberWithInteger:count];
			[buffer appendFormat:@"%d:%@:%llX:%X:%X:",
								count,
								info.file.name,
								info.file.size,
								(unsigned int)[info.file.modifyTime timeIntervalSince1970],
								(unsigned int)info.file.attribute];
            //兼容 国产飞鸽
			//NSString* ext = [info.file makeExtendAttribute];
			//if ([ext length] > 0) {
				//[buffer appendString:ext];
//				[buffer appendString:@":"];
			//}
			[buffer appendString:@"\a"];
			TRC(@"Attachment(%@)", buffer);
			[attachManager addAttachment:info messageID:messageID];
			count++;
		}
		if ([buffer length] > 0) {
			option	= buffer;
			command |= IPMSG_FILEATTACHOPT;
		}
	}

	// 各ユーザに送信
	for (UserInfo* info in toUsers) {
		NSInteger mid = -1;
		// 送信
		if ((command & IPMSG_FILEATTACHOPT) && (info.supportsAttachment)) {
			mid = [self sendTo:info
					 messageID:msg.packetNo
					   command:command
					   message:msg.message
						option:option];
			if (mid >= 0) {
				[attachManager addUser:info
							 messageID:[NSNumber numberWithInteger:mid]];
			}
		} else {
			mid = [self sendTo:info
					 messageID:msg.packetNo
					   command:command
					   message:msg.message
						option:nil];
		}
		if (mid >= 0) {
			// 応答待ちメッセージ一覧に追加
			RetryInfo* retry = [RetryInfo infoWithCommand:command
													   to:info
												  message:msg.message
												   option:option];
			[sendList setObject:retry forKey:[NSNumber numberWithInteger:mid]];
			// タイマ発行
			[NSTimer scheduledTimerWithTimeInterval:RETRY_INTERVAL
											 target:self
										   selector:@selector(retryMessage:)
										   userInfo:[NSNumber numberWithInt:mid]
											repeats:YES];
		}
	}
}

// 応答タイムアウト時処理
- (void)retryMessage:(NSTimer*)timer
{
	NSNumber*	msgid		= [timer userInfo];
	RetryInfo*	retryInfo	= [sendList objectForKey:msgid];
	if (retryInfo) {
		if (retryInfo.retryCount >= RETRY_MAX) {
			NSInteger ret = NSRunCriticalAlertPanel(
								NSLocalizedString(@"Send.Retry.Title", nil),
								NSLocalizedString(@"Send.Retry.Msg", nil),
								NSLocalizedString(@"Send.Retry.OK", nil),
								NSLocalizedString(@"Send.Retry.Cancel", nil),
								nil, [retryInfo toUser].userName);
			if (ret == NSAlertAlternateReturn) {
				// 再送キャンセル
				// 応答待ちメッセージ一覧からメッセージのエントリを削除
				[sendList removeObjectForKey:msgid];
				// 添付情報破棄
				[[AttachmentServer sharedServer] removeAttachmentsByMessageID:msgid
																	 needLock:YES
																   clearTimer:YES];
				// タイマ解除
				[timer invalidate];
				return;
			}
			// リトライ階数をリセットして再試行
			retryInfo.retryCount = 0;
		}
		// 再送信
		[self sendTo:retryInfo.toUser
		   messageID:[msgid unsignedIntValue]
			 command:retryInfo.command
			 message:retryInfo.message
			  option:retryInfo.option];
		// リトライ回数インクリメント
		retryInfo.retryCount++;
	} else {
		// タイマ解除
		[timer invalidate];
	}
}

// 封書開封通知を送信
- (void)sendOpenSealMessage:(RecvMessage*)info
{
	if (info) {
		[self sendTo:[info fromUser]
		   messageID:-1
			 command:IPMSG_READMSG
			  number:info.packetNo];
	}
}

// 添付破棄通知を送信
- (void)sendReleaseAttachmentMessage:(RecvMessage*)info
{
	if (info) {
		[self sendTo:[info fromUser]
		   messageID:-1
			 command:IPMSG_RELEASEFILES
			  number:info.packetNo];
	}
}

// 一定時間後にENTRY応答を送信
- (void)sendAnsEntryAfter:(NSTimeInterval)aSecond to:(UserInfo*)toUser
{
	[NSTimer scheduledTimerWithTimeInterval:aSecond
									 target:self
								   selector:@selector(sendAnsEntry:)
								   userInfo:toUser
									repeats:NO];
}

- (void)sendAnsEntry:(NSTimer*)aTimer
{
	Config*		cfg			= [Config sharedConfig];
	NSString*	userName	= cfg.userName;
	NSString*	groupName	= cfg.groupName;

	if ([userName length] <= 0) {
		userName = NSUserName();
	}
	if ([groupName length] <= 0) {
		groupName = nil;
	}
	[self sendTo:[aTimer userInfo]
	   messageID:-1
		 command:IPMSG_ANSENTRY | IPMSG_FILEATTACHOPT | IPMSG_CAPUTF8OPT
		 message:userName
		  option:groupName];
}

/*----------------------------------------------------------------------------*
 * メッセージ受信
 *----------------------------------------------------------------------------*/

// 受信後実処理
- (void)processReceiveMessage
{
	Config*				config	= nil;
	RecvMessage*		msg		= nil;
	static NSString*	version	= nil;
	unsigned long		command;
	UserInfo*			fromUser;
	struct sockaddr_in*	from;
	int					packetNo;
	NSString*			appendix;
	char				buff[MAX_SOCKBUF];	// 受信バッファ
	int					len;
	struct sockaddr_in	addr;
	socklen_t			addrLen = sizeof(addr);

	// 受信
	len = recvfrom(sockUDP, buff, MAX_SOCKBUF, 0, (struct sockaddr*)&addr, &addrLen);
	if (len == -1) {
		ERR(@"recvFrom error(sock=%d)", sockUDP);
		return;
	}
	TRC(@"recv %u bytes", len);

	// 解析
	msg = [RecvMessage messageWithBuffer:buff length:len from:addr];
	if (!msg) {
		ERR(@"Receive Buffer parse error(%s)", buff);
		return;
	}
	TRC(@"recvdata parsed");
	TRC(@"\tfrom      = %@", [msg fromUser]);
	TRC(@"\tpacketNo  = %d", msg.packetNo);
	TRC(@"\tcommand   = 0x%08X", [msg command]);
	TRC(@"\tabsence   = %s", ([msg absence] ? "YES" : "NO"));
	TRC(@"\tsealed    = %s", ([msg sealed] ? "YES" : "NO"));
	TRC(@"\tlockec    = %s", ([msg locked] ? "YES" : "NO"));
	TRC(@"\tmulticast = %s", ([msg multicast] ? "YES" : "NO"));
	TRC(@"\tbroadcast = %s", ([msg broadcast] ? "YES" : "NO"));
	TRC(@"\tappendix  = %@", [msg appendix]);

	command		= [msg command];
	fromUser	= [msg fromUser];
	from		= &addr;
	packetNo	= msg.packetNo;
	appendix	= [msg appendix];
	config		= [Config sharedConfig];

	// 受信メッセージに応じた処理
	switch (GET_MODE(command)) {
	/*-------- 無処理メッセージ ---------*/
	case IPMSG_NOOPERATION:
		// NOP
		TRC(@"command=IPMSG_NOOPERATION > nop");
		break;
	/*-------- ユーザエントリ系メッセージ ---------*/
	case IPMSG_BR_ENTRY:
	case IPMSG_ANSENTRY:
	case IPMSG_BR_ABSENCE:
		if ([config matchRefuseCondition:fromUser]) {
			// 通知拒否ユーザにはBR_EXITを送って相手からみえなくする
			[self sendTo:from
			   messageID:-1
				 command:IPMSG_BR_EXIT|IPMSG_CAPUTF8OPT
					data:[self entryMessageData]];
		} else {
			if (GET_MODE(command) == IPMSG_BR_ENTRY) {
				if (ntohl(from->sin_addr.s_addr) != myIPAddress) {
					// 応答を送信（自分自身以外）
					NSTimeInterval	second	= 0.5;
					NSUInteger		userNum	= [[UserManager sharedManager] numberOfUsers];
					if ((userNum < 50) || ((myIPAddress ^ htonl(from->sin_addr.s_addr) << 8) == 0)) {
						// ユーザ数50人以下またはアドレス上位24bitが同じ場合 0 〜 1023 ms
						second = (1023 & rand()) / 1024.0;
					} else if (userNum < 300) {
						// ユーザ数が300人以下なら 0 〜 2047 ms
						second = (2047 & rand()) / 2048.0;
					} else {
						// それ以上は 0 〜 4095 ms
						second = (4095 & rand()) / 4096.0;
					}
					[self sendAnsEntryAfter:second to:fromUser];
				}
			}
			// ユーザ一覧に追加
			[[UserManager sharedManager] appendUser:fromUser];
			// バージョン情報問い合わせ
			[self sendTo:from messageID:-1 command:IPMSG_GETINFO data:nil];
		}
		break;
	case IPMSG_BR_EXIT:
		// ユーザ一覧から削除
		[[UserManager sharedManager] removeUser:fromUser];
		// 添付ファイルを削除
		[[AttachmentServer sharedServer] removeUser:fromUser];
		break;
	/*-------- ホストリスト関連 ---------*/
	case IPMSG_BR_ISGETLIST:
	case IPMSG_OKGETLIST:
	case IPMSG_GETLIST:
	case IPMSG_BR_ISGETLIST2:
		// NOP
		break;
	case IPMSG_ANSLIST:
		if ([msg hostList]) {
			UserManager*	userManager	= [UserManager sharedManager];
			NSArray*		userArray	= [msg hostList];
			int				i;
			for (i = 0; i < [userArray count]; i++) {
				UserInfo* newUser = [userArray objectAtIndex:i];
				if (![config matchRefuseCondition:newUser]) {
					[userManager appendUser:newUser];
				}
			}
		}
		if ([msg hostListContinueCount] > 0) {
			// 継続のGETLIST送信
			[self sendTo:fromUser
			   messageID:-1
				 command:IPMSG_GETLIST
				  number:[msg hostListContinueCount]];
		} else {
			// BR_ENTRY送信（受信したホストに教えるため）
			[self broadcastEntry];
		}
		break;
	/*-------- メッセージ関連 ---------*/
	case IPMSG_SENDMSG:		// メッセージ送信パケット
		if ((command & IPMSG_SENDCHECKOPT) &&
			!(command & IPMSG_AUTORETOPT) &&
			!(command & IPMSG_BROADCASTOPT)) {
			// RCVMSGを返す
			[self sendTo:fromUser
			   messageID:-1
				 command:IPMSG_RECVMSG
				  number:packetNo];
		}
		if (config.inAbsence &&
			!(command & IPMSG_AUTORETOPT) &&
			!(command & IPMSG_BROADCASTOPT)) {
			// 不在応答を返す
			[self sendTo:fromUser
			   messageID:-1
				 command:IPMSG_SENDMSG|IPMSG_AUTORETOPT
				 message:[config absenceMessageAtIndex:config.absenceIndex]
				  option:nil];
		}
		if ([msg isUnknownUser]) {
			// ユーザエントリ系メッセージをやりとりしていないユーザからの受信
			if ((command & IPMSG_NOADDLISTOPT) == 0) {
				// リストに追加するためにENTRYパケット送信
				[self sendTo:from
				   messageID:-1
					 command:IPMSG_BR_ENTRY|IPMSG_FILEATTACHOPT|IPMSG_CAPUTF8OPT
						data:[self entryMessageData]];
			}
		}
		[[NSApp delegate] receiveMessage:msg];
		break;
	case IPMSG_RECVMSG:		// メッセージ受信確認パケット
		// 応答待ちメッセージ一覧から受信したメッセージのエントリを削除
		[sendList removeObjectForKey:[NSNumber numberWithInt:[appendix intValue]]];
		break;
	case IPMSG_READMSG:		// 封書開封通知パケット
		if (command & IPMSG_READCHECKOPT) {
			// READMSG受信確認通知をとばす
			[self sendTo:fromUser messageID:-1 command:IPMSG_ANSREADMSG number:packetNo];
		}
		if (config.noticeSealOpened) {
			// 封書が開封されたダイアログを表示
			[[NoticeControl alloc] initWithTitle:NSLocalizedString(@"SealOpenDlg.title", nil)
										 message:[fromUser summaryString]
											date:nil];
		}
		break;
	case IPMSG_DELMSG:		// 封書破棄通知パケット
		// 無処理
		break;
	case IPMSG_ANSREADMSG:
		// READMSGの確認通知。やるべきことは特になし
		break;
	/*-------- 情報取得関連 ---------*/
	case IPMSG_GETINFO:		// 情報取得要求
		// バージョン情報のパケットを返す
		if (!version) {
			// なければ編集
			NSString*	v1	= [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
			NSString*	v2	= [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
			NSString*	ver	= [NSString stringWithFormat:@"%@(%@)", v1, v2];
			version	= [[NSString stringWithFormat:NSLocalizedString(@"Version.Msg.string", nil), ver] retain];
		}
		[self sendTo:fromUser
		   messageID:-1
			 command:IPMSG_SENDINFO
			 message:version
			  option:nil];
		break;
	case IPMSG_SENDINFO:	// バージョン情報
		// バージョン情報をユーザ情報に設定
		[[UserManager sharedManager] setVersion:appendix ofUser:fromUser];
		DBG(@"%@:%@ = %@", fromUser.logOnName, fromUser.hostName, appendix);
		break;
	/*-------- 不在関連 ---------*/
	case IPMSG_GETABSENCEINFO:
		// 不在文のパケットを返す
		if (config.inAbsence) {
			[self sendTo:fromUser
			   messageID:-1
				 command:IPMSG_SENDABSENCEINFO
				 message:[config absenceMessageAtIndex:config.absenceIndex]
				  option:nil];
		} else {
			[self sendTo:fromUser
			   messageID:-1
				 command:IPMSG_SENDABSENCEINFO
				 message:@"Not Absence Mode."
				  option:nil];
		}
		break;
	case IPMSG_SENDABSENCEINFO:
		// 不在情報をダイアログに出す
		[[NoticeControl alloc] initWithTitle:[fromUser summaryString]
									 message:appendix
										date:nil];
		break;
	/*-------- 添付関連 ---------*/
	case IPMSG_RELEASEFILES:	// 添付破棄通知
		[[AttachmentServer sharedServer] removeUser:fromUser
										  messageID:[NSNumber numberWithInt:[appendix intValue]]];
		break;
	/*-------- 暗号化関連 ---------*/
	case IPMSG_GETPUBKEY:		// 公開鍵要求
		DBG(@"command=IPMSG_GETPUBKEY:%@", appendix);
		break;
	case IPMSG_ANSPUBKEY:
		DBG(@"command~IPMSG_ANSPUBKEY:%@", appendix);
		break;
	/*-------- その他パケット／未知パケット（を受信） ---------*/
	default:
		ERR(@"Unknown command Received(%@)", msg);
		break;
	}
}

- (void)shutdownServer
{
	if (!serverShutdown) {
		DBG(@"Shutdown MessageRecvServer...");
		serverShutdown = YES;
		[serverLock lock];	// ロック獲得できるのはサーバスレッド終了後
		DBG(@"MessageRecvServer finished.");
		[serverLock unlock];
		if (sockUDP != -1) {
			close(sockUDP);
			sockUDP = -1;
		}
	} else {
		DBG(@"Message Receive Server already down.");
	}
}

// メッセージ受信スレッド
- (void)serverThread:(NSArray*)portArray
{
	NSAutoreleasePool*	pool = [[NSAutoreleasePool alloc] init];
	fd_set				fdSet;
	struct timeval		tv;
	int					ret;
	NSConnection*		conn = [[NSConnection alloc] initWithReceivePort:[portArray objectAtIndex:0]
																sendPort:[portArray objectAtIndex:1]];
	id					proxy = [conn rootProxy];

	[serverLock lock];

	DBG(@"MessageRecvThread start.");
	while (!serverShutdown) {
		FD_ZERO(&fdSet);
		FD_SET(sockUDP, &fdSet);
		tv.tv_sec	= 1;
		tv.tv_usec	= 0;
		ret = select(sockUDP + 1, &fdSet, NULL, NULL, &tv);
		if (ret < 0) {
			ERR(@"select error(%d)", ret);
			continue;
		}
		if (ret == 0) {
			// タイムアウト
			continue;
		}
		@try {
			[proxy processReceiveMessage];
		} @catch (NSException* exception) {
			ERR(@"%@", exception);
		}
	}
	DBG(@"MessageRecvThread end.");

	[serverLock unlock];

	[conn release];
	[pool release];
}

/*----------------------------------------------------------------------------*
 * 情報取得関連
 *----------------------------------------------------------------------------*/

- (int)myPortNo {
	return myPortNo;
}

- (NSString*)myHostName {
	if (myHostName) {
		return myHostName;
	}
	return @"";
}

/*----------------------------------------------------------------------------*
 * メッセージ解析関連
 *----------------------------------------------------------------------------*/

// 受信Rawデータの分解
+ (BOOL)parseReceiveData:(char*)buffer length:(int)len into:(IPMsgData*)data
{
	char* work	= buffer;
	char* ptr	= buffer;
	if (!buffer || !data || (len <= 0)) {
		return NO;
	}

	// バージョン番号
	data->version = strtoul(ptr, &work, 16);
	if (*work != ':') {
		return NO;
	}
	ptr = work + 1;

	// パケット番号
	data->packetNo = strtoul(ptr, &work, 16);
	if (*work != ':') {
		return NO;
	}
	ptr = work + 1;

	// ログインユーザ名
	work = strchr(ptr, ':');
	if (!work) {
		return NO;
	}
	*work = '\0';
	strncpy(data->userName, ptr, sizeof(data->userName) - 1);
	ptr = work + 1;

	// ホスト名
	work = strchr(ptr, ':');
	if (!work) {
		return NO;
	}
	*work = '\0';
	strncpy(data->hostName, ptr, sizeof(data->hostName) - 1);
	ptr = work + 1;

	// コマンド番号
	data->command = strtoul(ptr, &work, 10);
	if (*work != ':') {
		return NO;
	}
	ptr = work + 1;

	// 拡張部
	strncpy(data->extension, ptr, sizeof(data->extension) - 1);

	return YES;
}

- (NSData*)entryMessageData
{
	Config*				config	= [Config sharedConfig];
	NSMutableData*		data	= [NSMutableData dataWithCapacity:128];
	NSString*			user	= config.userName;
	NSString*			group	= config.groupName;
	NSString*			absence	= @"";
	const char*			str		= NULL;
	NSMutableString*	utf8Str	= [NSMutableString stringWithCapacity:256];

	if ([user length] <= 0) {
		user = NSUserName();
	}
	if (config.inAbsence) {
		absence = [NSString stringWithFormat:@"[%@]", [config absenceTitleAtIndex:config.absenceIndex]];
	}

	// ニックネーム
	str = [user SJISString];
	[data appendBytes:str length:strlen(str)];
	if ([absence length] > 0) {
		str = [absence SJISString];
		[data appendBytes:str length:strlen(str)];
	}

	// グループ化拡張セパレータ
	[data appendBytes:"\0" length:1];

	// グループ名
	if ([group length] > 0) {
		str = [group SJISString];
		[data appendBytes:str length:strlen(str)];
	}

	// UTF-8拡張セパレータ
	[data appendBytes:"\0\n" length:2];

	// UTF-8文字列
	[utf8Str appendFormat:@"UN:%@\n", NSUserName()];
	[utf8Str appendFormat:@"HN:%@\n", myHostName];
	[utf8Str appendFormat:@"NN:%@%@\n", user, absence];
	if ([group length] > 0) {
		[utf8Str appendFormat:@"GN:%@\n", group];
	}
	str = [utf8Str UTF8String];
	[data appendBytes:str length:strlen(str)];
	[data appendBytes:"\0" length:1];

	return data;
}

- (BOOL)updateHostName
{
	CFStringRef		key		= SCDynamicStoreKeyCreateHostNames(NULL);
	NSDictionary*	newVal	= [(NSDictionary*)SCDynamicStoreCopyValue(scDynStore, key) autorelease];
	CFRelease(key);
	if (newVal) {
		NSString* newName = [newVal objectForKey:(NSString*)kSCPropNetLocalHostName];
		if (newName) {
			if (![newName isEqualToString:myHostName]) {
				[myHostName autorelease];
				myHostName = [newName copy];
				return YES;
			}
		}
	}
	return NO;
}

- (_NetUpdateState)updateIPAddress
{
	_NetUpdateState	state;
	CFStringRef		key;
	CFDictionaryRef	value;
	CFArrayRef		addrs;
	NSString*		addr;
	struct in_addr	inAddr;
	unsigned long	newAddr = 0;
#ifdef IPMSG_DEBUG
	unsigned long	oldAddr = myIPAddress;
#endif

	// PrimaryNetworkInterface更新
	state = [self updatePrimaryNIC];
	switch (state) {
		case _NET_LINK_LOST:
			// クリアして復帰
			[scKeyIFIPv4 release];
			scKeyIFIPv4	= nil;
			myIPAddress	= 0;
			return _NET_LINK_LOST;
		case _NET_NO_CHANGE_IN_UNLINK:
			// 変更はないがリンクしていないので復帰
			return _NET_NO_CHANGE_IN_UNLINK;
		case _NET_NO_CHANGE_IN_LINK:
			// 変更はないのでクリアせずに進む
			// (先での変更の可能性があるため）
			break;
		case _NET_LINK_GAINED:
		case _NET_PRIMARY_IF_CHANGED:
			// リンクの検出またはNICの切り替えが発生したので一度クリアする
			[scKeyIFIPv4 release];
			scKeyIFIPv4	= nil;
			myIPAddress	= 0;
			break;
		default:
			ERR(@"Invalid change status(%d)", state);
			[scKeyIFIPv4 release];
			scKeyIFIPv4	= nil;
			myIPAddress	= 0;
			if (!primaryNIC) {
				// リンク消失扱いにして復帰
				return _NET_LINK_LOST;
			} else {
				// 一応NICが変わったものとして扱う
				state = _NET_PRIMARY_IF_CHANGED;
			}
			break;
	}

	// State:/Network/Interface/<PrimaryNetworkInterface>/IPv4 キー編集
	if (!scKeyIFIPv4) {
		key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL,
															kSCDynamicStoreDomainState,
															(CFStringRef)primaryNIC,
															kSCEntNetIPv4);
		if (!key) {
			// 内部エラー
			ERR(@"Edit Key error (if=%@)", primaryNIC);
			[primaryNIC release];
			primaryNIC	= nil;
			myIPAddress	= 0;
			return _NET_LINK_LOST;
		}
		scKeyIFIPv4 = (NSString*)key;
	}

	// State:/Network/Interface/<PrimaryNetworkInterface>/IPv4 取得
	value = (CFDictionaryRef)SCDynamicStoreCopyValue(scDynStore, (CFStringRef)scKeyIFIPv4);
	if (!value) {
		// 値なし（ありえないはず）
		ERR(@"value get error (%@)", scKeyIFIPv4);
		[primaryNIC release];
		[scKeyIFIPv4 release];
		primaryNIC	= nil;
		scKeyIFIPv4	= nil;
		myIPAddress	= 0;
		return _NET_LINK_LOST;
	}

	// Addressesプロパティ取得
	addrs = (CFArrayRef)CFDictionaryGetValue(value, kSCPropNetIPv4Addresses);
	if (!addrs) {
		// プロパティなし
		ERR(@"prop get error (%@ in %@)", (NSString*)kSCPropNetIPv4Addresses, scKeyIFIPv4);
		CFRelease(value);
		[primaryNIC release];
		[scKeyIFIPv4 release];
		primaryNIC	= nil;
		scKeyIFIPv4	= nil;
		myIPAddress	= 0;
		return _NET_LINK_LOST;
	}

	// IPアドレス([0])取得
	addr = (NSString*)CFArrayGetValueAtIndex(addrs, 0);
	if (!addr) {
		ERR(@"[0] not exist (in %@)", (NSString*)kSCPropNetIPv4Addresses);
		CFRelease(value);
		[primaryNIC release];
		[scKeyIFIPv4 release];
		primaryNIC	= nil;
		scKeyIFIPv4	= nil;
		myIPAddress	= 0;
		return _NET_LINK_LOST;
	}
	if (inet_aton([addr UTF8String], &inAddr) == 0) {
		ERR(@"IP Address format error(%@)", addr);
		CFRelease(value);
		[primaryNIC release];
		[scKeyIFIPv4 release];
		primaryNIC	= nil;
		scKeyIFIPv4	= nil;
		myIPAddress	= 0;
		return _NET_LINK_LOST;
	}
	newAddr = ntohl(inAddr.s_addr);

	CFRelease(value);

	if (myIPAddress != newAddr) {
		DBG(@"IPAddress changed (%lu.%lu.%lu.%lu -> %lu.%lu.%lu.%lu)",
				((oldAddr >> 24) & 0x00FF), ((oldAddr >> 16) & 0x00FF),
				((oldAddr >> 8) & 0x00FF), (oldAddr & 0x00FF),
				((newAddr >> 24) & 0x00FF), ((newAddr >> 16) & 0x00FF),
				((newAddr >> 8) & 0x00FF), (newAddr & 0x00FF));
		myIPAddress = newAddr;
		// ステータスチェック（必要に応じて変更）
		switch (state) {
			case _NET_LINK_GAINED:
			case _NET_PRIMARY_IF_CHANGED:
				// そのまま（より大きな変更なので）
				break;
			case _NET_NO_CHANGE_IN_LINK:
			default:
				// IPアドレスは変更になったのでステータス変更
				state = _NET_IP_ADDRESS_CHANGED;
				break;
		}
	}

	return state;
}

- (_NetUpdateState)updatePrimaryNIC
{
	CFDictionaryRef	value		= NULL;
	CFStringRef		primaryIF	= NULL;

	// State:/Network/Global/IPv4 を取得
	value = (CFDictionaryRef)SCDynamicStoreCopyValue(scDynStore,
													 (CFStringRef)scKeyNetIPv4);
	if (!value) {
		// キー自体がないのは、すべてのネットワークI/FがUnlink状態
		if (primaryNIC) {
			// いままではあったのに無くなった
			DBG(@"All Network I/F becomes unlinked");
			[primaryNIC release];
			primaryNIC = nil;
			return _NET_LINK_LOST;
		}
		// もともと無いので変化なし
		return _NET_NO_CHANGE_IN_UNLINK;
	}

	// PrimaryNetwork プロパティを取得
	primaryIF = (CFStringRef)CFDictionaryGetValue(value,
												  kSCDynamicStorePropNetPrimaryInterface);
	if (!primaryIF) {
		// この状況が発生するのか不明（ありえないと思われる）
		ERR(@"Not exist prop %@", kSCDynamicStorePropNetPrimaryInterface);
		CFRelease(value);
		if (primaryNIC) {
			// いままではあったのに無くなった
			DBG(@"All Network I/F becomes unlinked");
			[primaryNIC release];
			primaryNIC = nil;
			return _NET_LINK_LOST;
		}
		// もともと無いので変化なし
		return _NET_NO_CHANGE_IN_UNLINK;
	}

	CFRetain(primaryIF);
	CFRelease(value);

	if (!primaryNIC) {
		// ネットワークが無い状態からある状態になった
		primaryNIC = (NSString*)primaryIF;
		DBG(@"A Network I/F becomes linked");
		return _NET_LINK_GAINED;
	}

	if (![primaryNIC isEqualToString:(NSString*)primaryIF]) {
		// 既にあるが変わった
		DBG(@"Primary Network I/F changed(%@ -> %@)", primaryNIC, (NSString*)primaryIF);
		[primaryNIC autorelease];
		primaryNIC = (NSString*)primaryIF;
		return _NET_PRIMARY_IF_CHANGED;
	}

	// これまでと同じ（接続済みで変化なし）
	CFRelease(primaryIF);

	return _NET_NO_CHANGE_IN_LINK;
}

- (void)systemConfigurationUpdated:(NSArray*)changedKeys
{
	unsigned i;
	for (i = 0; i < [changedKeys count]; i++) {
		NSString* key = (NSString*)[changedKeys objectAtIndex:i];
		if ([key isEqualToString:scKeyNetIPv4]) {
			_NetUpdateState			ret;
			NSNotificationCenter*	nc;
			DBG(@"<SC>NetIFStatus changed (key[%d]:%@)", i, key);
			ret = [self updateIPAddress];
			nc	= [NSNotificationCenter defaultCenter];
			switch (ret) {
				case _NET_NO_CHANGE_IN_LINK:
					// なにもしない
					DBG(@" no effects (in link status)");
					break;
				case _NET_NO_CHANGE_IN_UNLINK:
					// なにもしない
					DBG(@" no effects (in unlink status)");
					break;
				case _NET_PRIMARY_IF_CHANGED:
					// NICが切り替わったたのでユーザリストを更新する
					DBG(@" NIC Changed -> Referesh UserList");
					[[UserManager sharedManager] removeAllUsers];
					[self broadcastEntry];
					break;
				case _NET_IP_ADDRESS_CHANGED:
					// IPに変更があったのでユーザリストを更新する
					DBG(@" IPAddress Changed -> Referesh UserList");
					[[UserManager sharedManager] removeAllUsers];
					[self broadcastEntry];
					break;
				case _NET_LINK_GAINED:
					// ネットワーク環境に繋がったので通知してユーザリストを更新する
					[nc postNotificationName:NOTICE_NETWORK_GAINED object:nil];
					DBG(@" Network Gained -> Referesh UserList");
					[self broadcastEntry];
					break;
				case _NET_LINK_LOST:
					// つながっていたが接続がなくなったので通知
					[nc postNotificationName:NOTICE_NETWORK_LOST object:nil];
					DBG(@" Network Lost -> Remove Users");
					[[UserManager sharedManager] removeAllUsers];
					break;
				default:
					ERR(@" Unknown Status(%d)", ret);
					break;
			}
		} else if ([key isEqualToString:scKeyHostName]) {
			if ([self updateHostName]) {
				DBG(@"<SC>HostName changed (key[%d]:%@)", i, key);
				[[NSNotificationCenter defaultCenter] postNotificationName:NOTICE_HOSTNAME_CHANGED
																	object:nil];
				[self broadcastAbsence];
			}
		} else {
			DBG(@"<SC>No action defined for key[%d]:%@", i, key);
		}
	}
}

@end

/*============================================================================*
 * ローカル関数実装
 *============================================================================*/

void _DynamicStoreCallback(SCDynamicStoreRef	store,
						   CFArrayRef			changedKeys,
						   void*				info)
{
	MessageCenter* self = (MessageCenter*)info;
	[self systemConfigurationUpdated:(NSArray*)changedKeys];
}
