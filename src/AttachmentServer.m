/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AttachmentServer.m
 *	Module		: 送信添付ファイル管理クラス
 *============================================================================*/

#import "AttachmentServer.h"
#import "IPMessenger.h"
#import "Attachment.h"
#import "AttachmentFile.h"
#import "MessageCenter.h"
#import "UserManager.h"
#import "UserInfo.h"
#import "Config.h"
#import "NSStringIPMessenger.h"
#import "DebugLog.h"

#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <arpa/inet.h>

static BOOL valid = FALSE;

// IPMsgファイル送信依頼情報
typedef struct {
	unsigned	messageID;			// メッセージID
	unsigned	fileID;				// ファイルID
	unsigned	offset;				// オフセット位置

} IPMsgAttachRequest;

/*============================================================================*
 * プライベートメソッド定義
 *============================================================================*/

@interface AttachmentServer(Private)
- (BOOL)sendFile:(AttachmentFile*)file to:(int)sock sendHeader:(BOOL)flag;

// 添付ファイルサーバ関連
- (void)serverThread:(id)obj;
- (BOOL)sendFile:(AttachmentFile*)file to:(int)sock useUTF8:(BOOL)flag;
- (BOOL)sendDirectory:(AttachmentFile*)file to:(int)sock useUTF8:(BOOL)flag;
- (BOOL)sendFileHeader:(AttachmentFile*)file to:(int)sock useUTF8:(BOOL)flag;
- (BOOL)sendFileData:(AttachmentFile*)file to:(int)sock;
- (void)attachSendThread:(id)obj;
- (BOOL)parseAttachRequest:(NSString*)buffer into:(IPMsgAttachRequest*)req;

// その他
- (void)fireAttachListChangeNotice;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation AttachmentServer

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/

// 共有インスタンス獲得
+ (AttachmentServer*)sharedServer {
	static AttachmentServer* sharedManager = nil;
	if (!sharedManager) {
		sharedManager = [[AttachmentServer alloc] init];
	}
	return sharedManager;
}

// 有効チェック
+ (BOOL)isAvailable {
	return valid;
}

// サーバ停止
- (void)shutdownServer {
	DBG(@"Shutdown Attachment Server...");
	shutdown = YES;
	[serverLock lock];	// サーバロックがとれるのはサーバスレッドが終了した時
	DBG(@"Attachment Server finished.");
	[serverLock unlock];
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)init {
	int					sockopt	= 1;		// ソケットオプション
	struct sockaddr_in	addr;				// バインド用アドレス
	int					portNo;				// ポート番号

	// 変数初期化
	self		= [super init];
	attachDic	= [[NSMutableDictionary alloc] init];
	lockObj		= [[NSLock alloc] init];
	serverLock	= [[NSLock alloc] init];
	serverSock	= -1;
	shutdown	= FALSE;
	portNo		= [[MessageCenter sharedCenter] myPortNo];
	fileManager	= [NSFileManager defaultManager];
	if (portNo <= 0) {
		portNo = IPMSG_DEFAULT_PORT;
	}

	// ソケットオープン
	if ((serverSock = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
		ERR(@"serverSock:socket error");
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSRunCriticalAlertPanel(NSLocalizedString(@"Err.TCPSocketOpen.title", nil),
								NSLocalizedString(@"Err.TCPSocketOpen.msg", nil),
								NSLocalizedString(@"Err.TCPSocketOpen.ok", nil),
								nil, nil);
		return self;
	}

	// ソケットバインドアドレスの用意
	memset(&addr, 0, sizeof(addr));
	addr.sin_family			= AF_INET;
	addr.sin_addr.s_addr	= htonl(INADDR_ANY);
	addr.sin_port			= htons(portNo);

	// ソケットバインド
	if (bind(serverSock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
		ERR(@"serverSock:bind error");
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSRunCriticalAlertPanel(
							NSLocalizedString(@"Err.TCPSocketBind.title", nil),
							NSLocalizedString(@"Err.TCPSocketBind.msg", nil),
							NSLocalizedString(@"Err.TCPSocketBind.ok", nil),
							nil, nil, portNo);
		return self;
	}

	// REUSE ADDR
	sockopt = 1;
	setsockopt(serverSock, SOL_SOCKET, SO_REUSEADDR, &sockopt, sizeof(sockopt));

	// サーバ初期化
	if (listen(serverSock, 5) != 0) {
		ERR(@"serverSock:listen error");
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSRunCriticalAlertPanel(
							NSLocalizedString(@"Err.TCPSocketListen.title", nil),
							NSLocalizedString(@"Err.TCPSocketListen.msg", nil),
							NSLocalizedString(@"Err.TCPSocketListen.ok", nil),
							nil, nil);
		return self;
	}

	// 添付要求受信スレッド
	[NSThread detachNewThreadSelector:@selector(serverThread:) toTarget:self withObject:nil];

	valid = YES;

	return self;
}

// 解放
- (void)dealloc {
// 全タイマストップは？
	[attachDic release];
	[lockObj release];
	[serverLock release];
	if (serverSock != -1) {
		close(serverSock);
	}
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * 送信添付ファイル情報管理
 *----------------------------------------------------------------------------*/

// 添付ファイル管理タイムアウト
- (void)clearAttachmentByTimeout:(id)aTimer {
	[self removeAttachmentsByMessageID:(NSNumber*)[aTimer userInfo] needLock:YES clearTimer:NO];
}

// 送信添付ファイル追加
- (void)addAttachment:(Attachment*)attach messageID:(NSNumber*)mid {
	if (attach && mid) {
		NSMutableDictionary* dic;
		[lockObj lock];
		dic = [attachDic objectForKey:mid];
		if (!dic) {
			// 既に同一メッセージIDの管理情報がない場合
			NSTimer* timer;
			// 新しい下位辞書の作成／登録
			dic = [NSMutableDictionary dictionary];
			if (dic) {
				[attachDic setObject:dic forKey:mid];
			} else {
				ERR(@"allocation/init error(dic)");
			}
			// 破棄タイマの設定
			timer = [NSTimer scheduledTimerWithTimeInterval:(24 * 60 * 60)
													 target:self
												   selector:@selector(clearAttachmentByTimeout:)
												   userInfo:mid
													repeats:NO];
			if (timer) {
				[dic setObject:timer forKey:@"Timer"];
			} else {
				ERR(@"release timer alloc/init error");
			}
		}
		if (dic) {
			// 添付管理情報の追加
			[dic setObject:attach forKey:[attach fileID]];
			[self fireAttachListChangeNotice];
		}
		[lockObj unlock];
	}
}

- (void)removeAttachmentByMessageID:(NSNumber*)mid {
	[self removeAttachmentsByMessageID:mid needLock:YES clearTimer:YES];
}

- (void)removeAttachmentByMessageID:(NSNumber*)mid fileID:(NSNumber*)fid {
	NSMutableDictionary* dic;
	[lockObj lock];
	// メッセージIDに対応する下位辞書の検索
	dic = [attachDic objectForKey:mid];
	if (dic) {
		[dic removeObjectForKey:fid];
		if ([dic count] <= 1) {
			// 添付情報がなくなった場合(Timerはあるはず)
			[self removeAttachmentsByMessageID:mid needLock:NO clearTimer:YES];
		}
		[self fireAttachListChangeNotice];
	} else {
		WRN(@"attach info not found(mid=%@)", mid);
	}
	[lockObj unlock];
}

// 指定メッセージID添付ファイル削除
- (void)removeAttachmentsByMessageID:(NSNumber*)mid needLock:(BOOL)lockFlag clearTimer:(BOOL)clearFlag {
	NSMutableDictionary* dic;
	if (lockFlag) {
		[lockObj lock];
	}
	// メッセージIDに対応する下位辞書の検索
	dic = [attachDic objectForKey:mid];
	if (dic) {
		if (clearFlag) {
		NSTimer* timer = [dic objectForKey:@"Timer"];
			// タイマストップ
			if (timer) {
				if ([timer isValid]) {
					[timer invalidate];
				}
			}
		}
		// 管理情報破棄
		[attachDic removeObjectForKey:mid];
		[self fireAttachListChangeNotice];
	} else {
		WRN(@"attach info not found(mid=%@)", mid);
	}
	if (lockFlag) {
		[lockObj unlock];
	}
}

// 送信添付ファイル検索
- (Attachment*)attachmentWithMessageID:(NSNumber*)mid fileID:(NSNumber*)fid {
	if (mid && fid) {
		NSMutableDictionary* dic = [attachDic objectForKey:mid];
		if (dic) {
			return [dic objectForKey:fid];
		}
	}
	return nil;
}

/*----------------------------------------------------------------------------*
 * 送信ユーザ管理
 *----------------------------------------------------------------------------*/

- (void)addUser:(UserInfo*)user messageID:(NSNumber*)mid {
	NSMutableDictionary* dic;
	[lockObj lock];
	dic = [attachDic objectForKey:mid];
	if (dic) {
		NSArray*	keys = [dic allKeys];
		int			i;
		for (i = 0; i < [keys count]; i++) {
			Attachment* attach;
			id			fid = [keys objectAtIndex:i];
			if ([fid isEqual:@"Timer"]) {
				continue;
			}
			attach = [dic objectForKey:fid];
			if (attach) {
				if (![attach containsUser:user]) {
					[attach addUser:user];
				} else {
					ERR(@"attach send user already exist(%@,%@,%@)", mid, fid, user);
				}
				[self fireAttachListChangeNotice];
			} else {
				ERR(@"attach item not found(%@,%@)", mid, fid);
			}
		}
	} else {
		ERR(@"attach mid not found(%@)", mid);
	}
	[lockObj unlock];
}

- (BOOL)containsUser:(UserInfo*)user messageID:(NSNumber*)mid fileID:(NSNumber*)fid {
	NSMutableDictionary* dic = [attachDic objectForKey:mid];
	if (dic) {
		Attachment* item = [dic objectForKey:fid];
		if (item) {
			return [item containsUser:user];
		} else {
			ERR(@"attach item not found(%@,%@)", mid, fid);
		}
	} else {
		ERR(@"attach mid not found(%@)", mid);
	}
	return NO;
}

// 添付ファイル送信ユーザ削除
- (void)removeUser:(UserInfo*)user {
	NSEnumerator* keys = [attachDic keyEnumerator];
	id key;
	while ((key = [keys nextObject])) {
		[self removeUser:user messageID:key];
	}
}

// 添付ファイル送信ユーザ削除
- (void)removeUser:(UserInfo*)user messageID:(NSNumber*)mid {
	NSMutableDictionary* dic;
	[lockObj lock];
	dic = [attachDic objectForKey:mid];
	if (dic) {
		NSArray*	keys = [dic allKeys];
		int			i;
		for (i = 0; i < [keys count]; i++) {
			Attachment*	item;
			id			fid = [keys objectAtIndex:i];
			if ([fid isEqual:@"Timer"]) {
				continue;
			}
			item = [dic objectForKey:fid];
			if (item) {
				if ([item containsUser:user]) {
					[item removeUser:user];
					if ([item numberOfUsers] <= 0) {
						DBG(@"all user finished.(%@,%@)remove", mid, fid);
						[dic removeObjectForKey:fid];
						if ([dic count] <= 1) {
							// 添付情報がなくなった場合(Timerはあるはず)
							[self removeAttachmentsByMessageID:mid needLock:NO clearTimer:YES];
						}
					}
					[self fireAttachListChangeNotice];
				}
			} else {
				ERR(@"attach item not found(%@,%@)", mid, fid);
			}
		}
	} else {
		ERR(@"attach mid not found(%@)", mid);
	}
	[lockObj unlock];
}

// 添付ファイル送信ユーザ削除
- (void)removeUser:(UserInfo*)user messageID:(NSNumber*)mid fileID:(NSNumber*)fid {
	NSMutableDictionary* dic;
	[lockObj lock];
	dic = [attachDic objectForKey:mid];
	if (dic) {
		Attachment* item = [dic objectForKey:fid];
		if (item) {
			if ([item containsUser:user]) {
				[item removeUser:user];
				if ([item numberOfUsers] <= 0) {
					[dic removeObjectForKey:fid];
					if ([dic count] <= 1) {
						// 添付情報がなくなった場合(Timerはあるはず)
						[self removeAttachmentsByMessageID:mid needLock:NO clearTimer:YES];
					}
				}
				[self fireAttachListChangeNotice];
			} else {
				ERR(@"attach send user not found(%@,%@,%@)", mid, fid, user);
			}
		} else {
			ERR(@"attach item not found(%@,%@)", mid, fid);
		}
	} else {
		ERR(@"attach mid not found(%@)", mid);
	}
	[lockObj unlock];
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

- (int)numberOfMessageIDs {
	return [attachDic count];
}

- (NSNumber*)messageIDAtIndex:(int)index {
	NSArray* keys = [attachDic allKeys];
	if ((index < 0) || (index >= [attachDic count])) {
		return nil;
	}
	return [keys objectAtIndex:index];
}

- (int)numberOfAttachmentsInMessageID:(NSNumber*)mid {
	NSDictionary* dic = [attachDic objectForKey:mid];
	return (dic != nil) ? ([dic count] - 1) : 0;
}

- (Attachment*)attachmentInMessageID:(NSNumber*)mid atIndex:(int)index {
	NSDictionary* dic = [attachDic objectForKey:mid];
	if (dic) {
		int			count = 0;
		int			i;
		NSArray*	vals = [dic allValues];
		for (i = 0; i < [vals count]; i++) {
			id val = [vals objectAtIndex:i];
			if ([val isKindOfClass:[Attachment class]]) {
				if (count == index) {
					return val;
				}
				count++;
			}
		}
	}
	return nil;
}

- (id)attachmentAtIndex:(int)index {
	int			count = 0;
	NSArray*	keys1;
	int			i;
	keys1 = [attachDic allKeys];
	for (i = 0; i < [keys1 count]; i++) {
		int				j;
		id				key1	= [keys1 objectAtIndex:i];
		NSDictionary*	dic		= [attachDic objectForKey:key1];
		NSArray*		keys2	= [dic allKeys];
		for (j = 0; j < [keys2 count]; j++) {
			id key2	= [keys2 objectAtIndex:j];
			id item = [dic objectForKey:key2];
			if ([item isKindOfClass:[Attachment class]]) {
				if (count == index) {
					return item;
				}
				count++;
			}
		}
	}
	return nil;
}

/*----------------------------------------------------------------------------*
 * ファイルサーバ（Private）
 *----------------------------------------------------------------------------*/

// 要求受付スレッド
- (void)serverThread:(id)obj {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	struct sockaddr_in	clientAddr;
	socklen_t			len = sizeof(clientAddr);
	fd_set				fdSet;
	struct timeval		tv;
	int					ret;

	[serverLock lock];

	DBG(@"ServerThread start.");
	while (!shutdown) {
		FD_ZERO(&fdSet);
		FD_SET(serverSock, &fdSet);
		tv.tv_sec	= 1;
		tv.tv_usec	= 0;
		ret = select(serverSock + 1, &fdSet, NULL, NULL, &tv);
		if (ret < 0) {
			ERR(@"serverThread:select error(%d)", ret);
			break;
		}
		if (ret == 0) {
			// タイムアウト
			continue;
		}
		if (FD_ISSET(serverSock, &fdSet)) {
			int newSock = accept(serverSock, (struct sockaddr*)&clientAddr, &len);
			if (newSock < 0) {
				ERR(@"serverThread:accept error(%d)", newSock);
				break;
			} else {
				NSNumber*	sockfd	= [NSNumber numberWithInt:newSock];
				NSNumber*	address = [NSNumber numberWithUnsignedLong:ntohl(clientAddr.sin_addr.s_addr)];
				NSArray*	param	= [NSArray arrayWithObjects:sockfd, address, nil];
				DBG(@"serverThread:FileRequest recv(sock=%@,address=%s)", sockfd, inet_ntoa(clientAddr.sin_addr));
				[NSThread detachNewThreadSelector:@selector(attachSendThread:) toTarget:self withObject:param];
			}
		}
	}
	DBG(@"ServerThread end.");

	[serverLock unlock];
	[pool release];
}

// ファイル送信スレッド
- (void)attachSendThread:(id)obj
{
	NSAutoreleasePool*	pool	= [[NSAutoreleasePool alloc] init];
	int					sock	= [[obj objectAtIndex:0] intValue];		// 送信ソケットディスクリプタ
	UInt32				ipAddr;
	UInt16				ipPort;
	struct sockaddr_in	addr;
	int					waitTime;										// タイムアウト管理
	fd_set				fdSet;											// ソケット監視用
	struct timeval		tv;												// ソケット監視用
	char				buf[256];										// リクエスト読み込みバッファ
	int					ret;

	DBG(@"start(fd=%d).", sock);

	ipAddr					= [[obj objectAtIndex:1] unsignedLongValue];
	ipPort					= [[MessageCenter sharedCenter] myPortNo];
	addr.sin_addr.s_addr	= htonl(ipAddr);
	addr.sin_port			= htons(ipPort);

	// パラメタチェック
	if (sock < 0) {
		ERR(@"no socket(%d)", sock);
		[pool release];
		[NSThread exit];
	}

	for (waitTime = 0; waitTime < 30; waitTime++) {
		// リクエスト受信待ち
		memset(buf, 0, sizeof(buf));
		FD_ZERO(&fdSet);
		FD_SET(sock, &fdSet);
		tv.tv_sec	= 1;
		tv.tv_usec	= 0;
		ret = select(sock + 1, &fdSet, NULL, NULL, &tv);
		if (ret < 0) {
			ERR(@"select error(%d)", ret);
			break;
		}
		if (ret == 0) {
			continue;
		}
		if (FD_ISSET(sock, &fdSet)) {
			NSString*			str;
			UserInfo*			user;
			NSNumber*			mid;
			NSNumber*			fid;
			Attachment*			attach;
			AttachmentFile*		file;
			IPMsgData			recvData;
			IPMsgAttachRequest	req;
			int					len;
			BOOL				useUTF8;

			// リクエスト読み込み
			len = recv(sock, buf, sizeof(buf) - 1, 0);
			if (len < 0) {
				ERR(@"recvError(%d)", len);
				break;
			}

			// リクエスト解析
			buf[len] = '\0';
			DBG(@"recvRequest(%s)", buf);
			if (![MessageCenter parseReceiveData:buf length:len into:&recvData]) {
				ERR(@"Command Parse Error(%s)", buf);
				break;
			}
			useUTF8 = (BOOL)((recvData.command & IPMSG_UTF8OPT) != 0);

			// ユーザの特定
			if (recvData.command & IPMSG_UTF8OPT) {
				str = [NSString stringWithUTF8String:recvData.userName];
			} else {
				str = [NSString stringWithSJISString:recvData.userName];
			}
			user = [[UserManager sharedManager] userForLogOnUser:str
														 address:ipAddr
															port:ipPort];
			if (!user) {
				ERR(@"User find error(%@/%s:%d)",
						str, inet_ntoa(addr.sin_addr), htons(addr.sin_port));
				break;
			}

			// 要求添付ファイル特定
			str = [NSString stringWithUTF8String:recvData.extension];
			if (![self parseAttachRequest:str into:&req]) {
				ERR(@"Attach parse Error(%@)", str);
				break;
			}
			mid		= [NSNumber numberWithInt:req.messageID];
			fid		= [NSNumber numberWithInt:req.fileID];
			attach	= [self attachmentWithMessageID:mid fileID:fid];
			if (!attach) {
				ERR(@"attach not found.(%@/%@)", mid, fid);
				break;
			}

			// 送信ユーザであるかチェック
//			if (![self containsUser:user messageID:mid fileID:fid]) {
//				ERR(@"user(%@) not contained.", user);
//				break;
//			}

			// ファイル送信
			file = [attach file];
			if (!file) {
				ERR(@"file invalid(nil)");
				break;
			}
			switch (GET_MODE(recvData.command)) {
			case IPMSG_GETFILEDATA:	// 通常ファイル
				if (![file isRegularFile]) {
					ERR(@"type is not file(%@)", file.path);
					break;
				}
				if ([self sendFileData:file to:sock]) {
					[self removeUser:user messageID:mid fileID:fid];
					DBG(@"File Request processing complete.");
				} else {
					ERR(@"sendFile error(%@)", file.path);
				}
				break;
			case IPMSG_GETDIRFILES:	// ディレクトリ
				if (![file isDirectory]) {
					ERR(@"type is not directory(%@)", file.path);
					break;
				}
				if ([self sendDirectory:file to:sock useUTF8:useUTF8]) {
					[self removeUser:user messageID:mid fileID:fid];
					DBG(@"Dir Request processing complete.");
				} else {
					ERR(@"sendDir error(%@)", file.path);
				}
				break;
			default:	// その他
				ERR(@"invalid command([0x%08lX],%@)", GET_MODE(recvData.command), file.path);
				break;
			}
			break;
		}
	}
	if (waitTime >= 30) {
		ERR(@"recv TimeOut.");
	}

	close(sock);
	DBG(@"finish.(fd=%d)", sock);
	[pool release];
}

// ディレクトリ送信
- (BOOL)sendDirectory:(AttachmentFile*)dir to:(int)sock useUTF8:(BOOL)utf8
{
	TRC(@"start dir(%@)", dir.path);

	// ヘッダ送信
	if (![self sendFileHeader:dir to:sock useUTF8:utf8]) {
		ERR(@"header send error(%@)", dir.path);
		return NO;
	}

	// ディレクトリ直下ファイル送信ループ
	NSArray* files = [fileManager contentsOfDirectoryAtPath:dir.path error:NULL];
	for (NSString* file in files) {
		NSString*		path;
		AttachmentFile*	child;
		NSDictionary*	attrs;
		NSString*		type;

		path	= [dir.path stringByAppendingPathComponent:file];
		child	= [AttachmentFile fileWithPath:path];
		if (!child) {
			ERR(@"child('%@') invalid", path);
			continue;
		}

		attrs	= [fileManager attributesOfItemAtPath:child.path error:NULL];
		type	= [attrs objectForKey:NSFileType];
		// 子ファイル
		if ([type isEqualToString:NSFileTypeRegular]) {
			// ヘッダ送信
			if (![self sendFileHeader:child to:sock useUTF8:utf8]) {
				ERR(@"header send error(%@)", child.path);
				return NO;
			}
			// ファイルデータ送信
			if (![self sendFileData:child to:sock]) {
				ERR(@"file send error(%@)", child.path);
				return NO;
			}
		}
		// 子ディレクトリ
		else if ([type isEqualToString:NSFileTypeDirectory]) {
			// ディレクトリ送信（再帰呼び出し）
			if (![self sendDirectory:child to:sock useUTF8:utf8]) {
				ERR(@"subdir send error(%@)", child.path);
				return NO;
			}
		}
		// 非サポート
		else {
			ERR(@"unsupported file type(%@,%@)", type, child.path);
			continue;
		}
	}

	// 親ディレクトリ復帰ヘッダ送信
	const char* dat = "000B:.:0:3:";	// IPMSG_FILE_RETPARENT = 0x3
	if (send(sock, dat, strlen(dat), 0) < 0) {
		ERR(@"to parent header send error(%s,%@)", dat, dir.path);
		return NO;
	}

	TRC(@"complete dir(%@)", dir.path);

	return YES;
}

// ファイル階層ヘッダ送信処理
- (BOOL)sendFileHeader:(AttachmentFile*)file to:(int)sock useUTF8:(BOOL)utf8
{
	// ヘッダ編集（ファイル名に":"は使えないのでエスケープ不要）
	NSString*	dh1	= [NSString stringWithFormat:@"%@:%llX:%X:%@:",
											   file.name,
											   file.size,
											   (unsigned int)file.attribute,
											   [file makeExtendAttribute]];
	NSUInteger	len	= strlen((utf8 ? [dh1 UTF8String] : [dh1 SJISString]));
	NSString*	dh2	= [NSString stringWithFormat:@"%04X:%@", len + 5, dh1];
	const char*	dat	= utf8 ? [dh2 UTF8String] : [dh2 SJISString];

	// ファイルヘッダ送信
	if (send(sock, dat, strlen(dat), 0) < 0) {
		ERR(@"header send error(%@)", dh2);
		return NO;
	}

	return YES;
}

// ファイルデータ送信処理
- (BOOL)sendFileData:(AttachmentFile*)file to:(int)sock
{
	NSFileHandle*	fileHandle;
	NSUInteger		size;

	// ファイルオープン
	fileHandle = [NSFileHandle fileHandleForReadingAtPath:file.path];
	if (!fileHandle) {
		ERR(@"sendFileData:Open Error(%@)", file.path);
		return NO;
	}

	// 送信単位サイズ（将来ユーザ調整可能に？)
	size = 8192;

	// 送信ループ
	while (YES) {
		// ファイル読み込み
		NSData*	data = [fileHandle readDataOfLength:size];
		if (!data) {
			ERR(@"sendFileData:Read Error(data is nil,path=%@)", file.path);
			[fileHandle closeFile];
			return NO;
		}
		// 送信完了チェック
		if ([data length] == 0) {
			TRC(@"SendFileComplete1(%@,size=%llu)", file.path, [file size]);
			break;
		}
		// データ送信
		if (send(sock, [data bytes], [data length], 0) < 0) {
			ERR(@"sendFileData:Send Error(path=%@)", file.path);
			[fileHandle closeFile];
			return NO;
		}
		if ([data length] != size) {
			// 送信完了
			TRC(@"SendFileComplete2(%@,size=%llu)", file.path, [file size]);
			break;
		}
	}

	[fileHandle closeFile];

	return YES;
}

// 添付送信リクエスト情報解析
- (BOOL)parseAttachRequest:(NSString*)buffer into:(IPMsgAttachRequest*)req
{
	NSScanner*	scanner;
	NSArray*	strs;
	NSString*	str;

	// リクエスト分解
	strs = [buffer componentsSeparatedByString:@":"];
	if ([strs count] < 3) {
		ERR(@"atach request format error(%@)", buffer);
		return NO;
	}

	// メッセージID
	str		= [strs objectAtIndex:0];
	scanner = [NSScanner scannerWithString:str];
	if (![scanner scanHexInt:&req->messageID]) {
		ERR(@"messageID parse error(%@)", str);
		return NO;
	}

	// ファイルID
	str		= [strs objectAtIndex:1];
	scanner = [NSScanner scannerWithString:str];
	if (![scanner scanHexInt:&req->fileID]) {
		ERR(@"fileID parse error(%@)", str);
		return NO;
	}

	// オフセット（フォルダの場合は来ない。本当はファイルとフォルダ分けて処理すべき）
	req->offset = 0;
	if ([strs count] >= 3) {
		str	= [strs objectAtIndex:2];
		if ([str length] > 0) {
			scanner = [NSScanner scannerWithString:str];
			if (![scanner scanHexInt:&req->offset]) {
				ERR(@"offset parse error(%@)", str);
				return NO;
			}
		}
	}

	TRC(@"request:messageID=%d,fileID=%d,offset=%d",
								req->messageID, req->fileID, req->offset);

	return YES;
}

/*----------------------------------------------------------------------------*
 * 内部利用（Private）
 *----------------------------------------------------------------------------*/

// 添付管理情報変更通知発行
- (void)fireAttachListChangeNotice
{
	[[NSNotificationCenter defaultCenter] postNotificationName:NOTICE_ATTACH_LIST_CHANGED
														object:nil];
}

@end
