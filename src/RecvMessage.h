/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: RecvMessage.h
 *	Module		: 受信メッセージクラス
 *============================================================================*/

#import <Foundation/Foundation.h>
#import <netinet/in.h>

@class UserInfo;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface RecvMessage : NSObject <NSCopying>
{
	UserInfo*			fromUser;		// 送信元ユーザ
	BOOL				unknownUser;	// 未知のユーザフラグ
	NSString*			logOnUser;		// ログイン名
	NSString*			hostName;		// ホスト名
	unsigned long		command;		// コマンド番号
	NSString*			appendix;		// 追加部
	NSString*			appendixOption;	// 追加部オプション
	NSMutableArray*		attachments;	// 添付ファイル
	NSMutableArray*		hostList;		// ホストリスト
	int					continueCount;	// ホストリスト継続ユーザ番号
	BOOL				needLog;		// ログ出力フラグ

	NSInteger			_packetNo;
	NSDate*				_date;
	struct sockaddr_in	_address;

}

@property(readonly)	NSInteger			packetNo;		// パケット番号
@property(readonly)	NSDate*				receiveDate;	// 受信日時
//@property(readonly)	struct sockaddr_in	fromAddress;	// 送信元アドレス

// ファクトリ
+ (RecvMessage*)messageWithBuffer:(const void*)buf
						   length:(NSUInteger)len
							 from:(struct sockaddr_in)addr;

// 初期化／解放
- (id)initWithBuffer:(const void*)buf
			  length:(NSUInteger)len
				from:(struct sockaddr_in)addr;

// getter（相手情報）
- (UserInfo*)fromUser;
- (BOOL)isUnknownUser;

// getter（共通）
//- (NSString*)logOnUser;
//- (NSString*)hostName;
- (unsigned long)command;
- (NSString*)appendix;
//- (NSString*)appendixOption;

// getter（IPMSG_SENDMSGのみ）
- (BOOL)sealed;
- (BOOL)locked;
- (BOOL)multicast;
- (BOOL)broadcast;
- (BOOL)absence;
- (NSArray*)attachments;

// getter（IPMSG_ANSLISTのみ）
- (NSArray*)hostList;
- (int)hostListContinueCount;

// その他
- (void)removeDownloadedAttachments;
- (BOOL)needLog;
- (void)setNeedLog:(BOOL)flag;

@end
