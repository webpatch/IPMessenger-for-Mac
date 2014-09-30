/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: RecvMessage.m
 *	Module		: 受信メッセージクラス
 *============================================================================*/

#import "RecvMessage.h"
#import "IPMessenger.h"
#import "Config.h"
#import "UserManager.h"
#import "UserInfo.h"
#import "Attachment.h"
#import "NSStringIPMessenger.h"
#import "DebugLog.h"

#import <netinet/in.h>
#import <arpa/inet.h>

@interface RecvMessage()
@property(assign,readwrite)	NSInteger			packetNo;
@property(assign,readwrite)	NSDate*				receiveDate;
@property(readwrite)		struct sockaddr_in	fromAddress;
@end

@implementation RecvMessage

@synthesize packetNo	= _packetNo;
@synthesize receiveDate	= _date;
@synthesize fromAddress	= _address;

/*============================================================================*
 * ファクトリ
 *============================================================================*/

// インスタンス生成
+ (RecvMessage*)messageWithBuffer:(const void*)buf length:(NSUInteger)len from:(struct sockaddr_in)addr {
	return [[[RecvMessage alloc] initWithBuffer:buf length:len from:addr] autorelease];
}

/*============================================================================*
 * 初期化／解放
 *============================================================================*/

// 初期化
- (id)initWithBuffer:(const void*)buf length:(NSUInteger)len from:(struct sockaddr_in)addr
{

	/*------------------------------------------------------------------------*
	 * 準備
	 *------------------------------------------------------------------------*/

	TRC(@"start parsing(buf=0x%08X,len=%u)--------", buf, len);

	// パラメタチェック
	if (!buf) {
		ERR(@"parameter error(buf is NULL)");
		[self release];
		return nil;
	}
	if (len <= 0) {
		ERR(@"parameter error(len is %d)", len);
		[self release];
		return nil;
	}

	self = [super init];
	if (!self) {
		ERR(@"self is nil([super init])");
		return self;
	}

	// メンバ初期化
	self.receiveDate	= [[NSDate date] retain];
	self.fromAddress	= addr;

	fromUser		= nil;
	unknownUser		= NO;
	logOnUser		= nil;
	hostName		= nil;
	command			= 0;
	appendix		= nil;
	appendixOption	= nil;
	attachments		= nil;
	hostList		= nil;
	continueCount	= 0;
	needLog			= [Config sharedConfig].standardLogEnabled;

	TRC(@"\treceiveDate   =%@", self.receiveDate);
	TRC(@"\tneedLog       =%s", (needLog ? "YES" : "NO"));

	// バッファコピー
	char buffer[len + 1];
	memcpy(buffer, buf, len);
	buffer[len] = '\0';
	while ((len > 0) && (buffer[len-1] == '\0')) {
		len--;		// 末尾余白削除
	}

	/*------------------------------------------------------------------------*
	 * バッファ解析
	 *------------------------------------------------------------------------*/

	char*	ptr;				// ワーク
	char*	tok;				// ワーク
	char*	message		= NULL;	// 追加部C文字列
	char*	subMessage	= NULL;	// 追加部オプションC文字列
	char*	subMessage2	= NULL;	// 追加部オプションUTF-8文字列

	// 追加部オプション
	if ((len + 1) - (strlen(buffer) + 1) > 0) {
		subMessage = &buffer[strlen(buffer) + 1];
		TRC(@"\tsubMessage   =\"%s\"(len=%d[%d,%d])", subMessage, (len + 1) - (strlen(buffer) + 1), len, strlen(buffer));
		if ((len + 1) - (strlen(buffer) + 1) - (strlen(subMessage) + 1) > 0) {
			subMessage2 = &subMessage[strlen(subMessage) + 2];
			TRC(@"\tsubMessage2  =\"%s\"(len=%d[%d,%d,%d])", subMessage2, (len + 1) - (strlen(buffer) + 1) - (strlen(subMessage) + 1), len, strlen(buffer), strlen(subMessage));
		}
	}

	// バージョン番号
	if (!(tok = strtok_r(buffer, MESSAGE_SEPARATOR, &ptr))) {
		ERR(@"msg:illegal format(version get error,\"%s\")", buf);
		[self release];
		return nil;
	}
	if (strtol(tok, NULL, 10) != IPMSG_VERSION) {
		ERR(@"msg:version invalid(%ld)", strtol(tok, NULL, 10));
		[self release];
		return nil;
	}
	TRC(@"\tversion       =%d", IPMSG_VERSION);

	// パケット番号
	if (!(tok = strtok_r(NULL, MESSAGE_SEPARATOR, &ptr))) {
		ERR(@"msg:illegal format(version get error,\"%s\")", buf);
		[self release];
		return nil;
	}
	self.packetNo = strtol(tok, NULL, 10);
	TRC(@"\tpacketNo      =%d", self.packetNo);

	// ログイン名
	if (!(tok = strtok_r(NULL, MESSAGE_SEPARATOR, &ptr))) {
		ERR(@"msg:illegal format(logOn get error,\"%s\")", buf);
		[self release];
		return nil;
	}
	logOnUser = [[NSString alloc] initWithSJISString:tok];
	TRC(@"\tlogOnUser     =%@", logOnUser);

	// ホスト名
	if (!(tok = strtok_r(NULL, MESSAGE_SEPARATOR, &ptr))) {
		ERR(@"msg:illegal format(host get error,\"%s\")", buf);
		[self release];
		return nil;
	}
	hostName = [[NSString alloc] initWithSJISString:tok];
	TRC(@"\thostName      =%@", hostName);

	// コマンド番号
	if (!(tok = strtok_r(NULL, MESSAGE_SEPARATOR, &ptr))) {
		ERR(@"msg:illegal format(command get error,\"%s\")", buf);
		[self release];
		return nil;
	}
	command = strtoul(tok, NULL, 10);
	TRC(@"\tcommand       =0x%08X", command);

	// 追加部
	message	= ptr;
	if (message) {
		if (command & IPMSG_UTF8OPT) {
			appendix = [[NSString alloc] initWithUTF8String:message];
		} else {
			appendix = [[NSString alloc] initWithSJISString:message];
		}
	}
	TRC(@"\tappendix      =%@", appendix);

	// 追加部オプション
	if (subMessage) {
		if (command & IPMSG_UTF8OPT) {
			appendixOption = [[NSString alloc] initWithUTF8String:subMessage];
		} else {
			appendixOption = [[NSString alloc] initWithSJISString:subMessage];
		}
	}
	TRC(@"\tappendixOption=%@", appendixOption);

	switch (GET_MODE(command)) {
		case IPMSG_BR_ENTRY:
		case IPMSG_BR_ABSENCE:
			if ((command & IPMSG_CAPUTF8OPT) && subMessage2) {
				// UTF8指定文字列があれば置き換え
				NSString*	utf8 = [NSString stringWithUTF8String:subMessage2];
				NSArray*	strs = [utf8 componentsSeparatedByString:@"\n"];
				for (NSString* str in strs) {
					if ([str length] <= 0) {
						continue;
					}
					NSArray*	kv	= [str componentsSeparatedByString:@":"];
					NSString*	key	= [kv objectAtIndex:0];
					NSString*	val	= [kv objectAtIndex:1];
					if ([key isEqualToString:@"UN"]) {
						[logOnUser release];
						logOnUser = [val copy];
						TRC(@"\tUTF8-UN  =%@", logOnUser);
					} else if ([key isEqualToString:@"HN"]) {
						[hostName release];
						hostName = [val copy];
						TRC(@"\tUTF8-HN  =%@", hostName);
					} else if ([key isEqualToString:@"NN"]) {
						[appendix release];
						appendix = [val copy];
						TRC(@"\tUTF8-NN  =%@", appendix);
					} else if ([key isEqualToString:@"GN"]) {
						[appendixOption release];
						appendixOption = [val copy];
						TRC(@"\tUTF8-GN  =%@", appendixOption);
					} else {
						WRN(@"unknown UTF8 entry kv(%@:%@)", key, val);
					}
				}
			}
			break;
	}

	// ユーザ特定
	fromUser = [[[UserManager sharedManager] userForLogOnUser:logOnUser
													  address:ntohl(self.fromAddress.sin_addr.s_addr)
														 port:ntohs(self.fromAddress.sin_port)] retain];
	if (!fromUser) {
		// 未知のユーザ
		unknownUser = YES;
		fromUser = [[UserInfo alloc] initWithUserName:nil
											groupName:nil
											 hostName:hostName
											logOnName:logOnUser
											  address:&addr
											  command:command];
	}

	/*------------------------------------------------------------------------*
	 * メッセージ種別による処理
	 *------------------------------------------------------------------------*/

	switch (GET_MODE(command)) {
	// エントリ系メッセージではユーザ情報を通知されたメッセージ（最新）に従って再作成する
	case IPMSG_BR_ENTRY:
	case IPMSG_ANSENTRY:
	case IPMSG_BR_ABSENCE:
		[fromUser release];
		fromUser = [[UserInfo alloc] initWithUserName:appendix
											groupName:appendixOption
											 hostName:hostName
											logOnName:logOnUser
											  address:&addr
											  command:command];
		break;
	// 添付ファイル付きの通常メッセージは添付を取り出し
	case IPMSG_SENDMSG:
		if ((command & IPMSG_FILEATTACHOPT) && subMessage) {
			NSString*	msg;
			NSArray*	msgs;
			if (command & IPMSG_UTF8OPT) {
				msg = [NSString stringWithUTF8String:subMessage];
			} else {
				msg = [NSString stringWithSJISString:subMessage];
			}
			// 区切りが":\a:"の場合と、":\a"の場合とありえる
			msgs = [msg componentsSeparatedByString:@":\a"];
			if ([msgs count] > 0) {
				NSMutableArray* array;
				array = [NSMutableArray arrayWithCapacity:[msgs count]];
				for (NSString* str in msgs) {
					TRC(@"attach string(%@)", str);
					if ([str length] <= 0) {
						TRC(@"attach empty1 -> continue");
						continue;
					}
					if ([str characterAtIndex:0] == ':') {
						// 区切りが":\a:"だった場合、先頭の:を削る
						str = [str substringFromIndex:1];
						TRC(@"attach striped(%@)", str);
						if ([str length] <= 0) {
							TRC(@"attach empty2 -> continue");
							continue;
						}
					}
					Attachment* attach = [Attachment attachmentWithMessage:str];
					if (attach) {
						[array addObject:attach];
					} else {
						ERR(@"attach str parse error.(%@)", str);
					}
				}
				if ([array count] > 0) {
					attachments = [array retain];
				}
			}
		}
		break;
	// ホストリストメッセージならリストを取り出し
	case IPMSG_ANSLIST:
		if (message) {
			NSArray*		lists		= [appendix componentsSeparatedByString:@"\a"];
			int				totalCount	= [[lists objectAtIndex:1] intValue];
			NSMutableArray*	array		= [[[NSMutableArray alloc] initWithCapacity:10] autorelease];
			if (totalCount > 0) {
				int				i;
				continueCount	= [[lists objectAtIndex:0] intValue];
				if ([lists count] < (unsigned)(totalCount * 7 + 2)) {
					WRN(@"hostlist:invalid data(items=%d,totalCount=%d,%@)", [lists count], totalCount, self);
					totalCount = ([lists count] - 2) / 7;
				}
				for (i = 0; i < totalCount; i++) {
					UserInfo* newUser = [UserInfo userWithHostList:lists fromIndex:(i * 7 + 2)];
					if (newUser) {
						[array addObject:newUser];
					}
				}
				if ([array count] > 0) {
					hostList = [array retain];
				}
			}
		}
		break;
	default:
		break;
	}

	TRC(@"end parsing----------------------------");

	return self;
}

// 解放
- (void)dealloc {
	[_date release];

	[fromUser release];
	[logOnUser release];
	[hostName release];
	[appendix release];
	[appendixOption release];
	[attachments release];
	[hostList release];
	[super dealloc];
}

/*============================================================================*
 * getter（相手情報）
 *============================================================================*/

// 送信元ユーザ
- (UserInfo*)fromUser {
	return fromUser;
}

// 未知のユーザからの受信かどうか
- (BOOL)isUnknownUser {
	return unknownUser;
}

/*============================================================================*
 * getter（共通）
 *============================================================================*/

// ログインユーザ
//- (NSString*)logOnUser {
//	return logOnUser;
//}

// ホスト名
//- (NSString*)hostName {
//	return hostName;
//}

// 受信コマンド
- (unsigned long)command {
	return command;
}

// 拡張部
- (NSString*)appendix {
	return appendix;
}

// 拡張部追加部
//- (NSString*)appendixOption {
//	return appendixOption;
//}

/*============================================================================*
 * getter（IPMSG_SENDMSGのみ）
 *============================================================================*/

// 封書フラグ
- (BOOL)sealed {
	return ((command & IPMSG_SECRETOPT) != 0);
}

// 施錠フラグ
- (BOOL)locked {
	return ((command & IPMSG_PASSWORDOPT) != 0);
}

// マルチキャストフラグ
- (BOOL)multicast {
	return ((command & IPMSG_MULTICASTOPT) != 0);
}

// ブロードキャストフラグ
- (BOOL)broadcast {
	return ((command & IPMSG_BROADCASTOPT) != 0);
}

// 不在フラグ
- (BOOL)absence {
	return ((command & IPMSG_AUTORETOPT) != 0);
}

// 添付ファイルリスト
- (NSArray*)attachments {
	return attachments;
}

/*============================================================================*
 * getter（IPMSG_ANSLISTのみ）
 *============================================================================*/

// ホストリスト
- (NSArray*)hostList {
	return hostList;
}

// ホストリスト継続番号
- (int)hostListContinueCount {
	return continueCount;
}

/*============================================================================*
 * その他
 *============================================================================*/

// ダウンロード完了済み添付ファイル削除
- (void)removeDownloadedAttachments {
	int index;
	for (index = [attachments count] - 1; index >= 0; index--) {
		Attachment* attach = [attachments objectAtIndex:index];
		if (attach.isDownloaded) {
			[attachments removeObjectAtIndex:index];
		}
	}
}

// ログ未出力フラグ
- (BOOL)needLog {
	return needLog;
}

// ログ出力済設定
- (void)setNeedLog:(BOOL)flag {
	needLog = flag;
}

/*============================================================================*
 * その他（親クラスオーバーライド）
 *============================================================================*/

// 等価判定
- (BOOL)isEqual:(id)obj {
	if ([obj isKindOfClass:[self class]]) {
		RecvMessage* target = obj;
		return ([fromUser isEqual:target->fromUser] &&
				(self.packetNo == target.packetNo));
	}
	return NO;
}

// オブジェクト文字列表現
- (NSString*)description {
	return [NSString stringWithFormat:@"RecvMessage:command=0x%08lX,PacketNo=%d,from=%@", command, self.packetNo, fromUser];
}

// オブジェクトコピー
- (id)copyWithZone:(NSZone*)zone {
	RecvMessage* newObj	= [[RecvMessage allocWithZone:zone] init];
	if (newObj) {
		newObj->_packetNo		= self->_packetNo;
		newObj->_date			= [self->_date retain];
		newObj->_address		= self->_address;

		newObj->fromUser		= [fromUser retain];
		newObj->unknownUser		= unknownUser;
		newObj->logOnUser		= [logOnUser retain];
		newObj->hostName		= [hostName retain];
		newObj->command			= command;
		newObj->appendix		= [appendix retain];
		newObj->appendixOption	= [appendixOption retain];
		newObj->attachments		= [attachments retain];
		newObj->hostList		= [hostList retain];
		newObj->continueCount	= continueCount;
		newObj->needLog			= needLog;
	} else {
		ERR(@"copy error(%@)", self);
	}

	return newObj;
}

@end
