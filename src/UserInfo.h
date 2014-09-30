/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: UserInfo.h
 *	Module		: ユーザ情報クラス
 *============================================================================*/

#import <Foundation/Foundation.h>
#import <netinet/in.h>

@class RecvMessage;

/*============================================================================*
 * プロパティ識別定義
 *============================================================================*/

extern NSString* const kIPMsgUserInfoUserNamePropertyIdentifier;
extern NSString* const kIPMsgUserInfoGroupNamePropertyIdentifier;
extern NSString* const kIPMsgUserInfoHostNamePropertyIdentifier;
extern NSString* const kIPMsgUserInfoLogOnNamePropertyIdentifier;
extern NSString* const kIPMsgUserInfoIPAddressPropertyIdentifier;
extern NSString* const kIPMsgUserInfoVersionPropertyIdentifer;

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface UserInfo : NSObject <NSCopying>
{
	NSString*			_userName;
	NSString*			_groupName;
	NSString*			_hostName;
	NSString*			_logOnName;
	struct sockaddr_in	_address;
	NSString*			_ipAddress;
	UInt32				_ipAddressNumber;
	UInt16				_portNo;
	NSString*			_version;
	BOOL				_absence;
	BOOL				_dialup;
	BOOL				_attachment;
	BOOL				_encrypt;
	BOOL				_UTF8;
}

@property(copy,readonly)	NSString*	userName;			// IPMsgユーザ名（ニックネーム）
@property(copy,readonly)	NSString*	groupName;			// IPMsgグループ名
@property(copy,readonly)	NSString*	hostName;			// マシン名
@property(copy,readonly)	NSString*	logOnName;			// ログインユーザ名
@property(readonly)	struct sockaddr_in	address;			// 接続アドレス
@property(copy,readonly)	NSString*	ipAddress;			// IPアドレス（文字列）
@property(readonly)			UInt32		ipAddressNumber;	// IPアドレス（数値）
@property(readonly)			UInt16		portNo;				// ポート番号
@property(copy,readwrite)	NSString*	version;			// バージョン情報
@property(readonly)			BOOL		inAbsence;			// 不在
@property(readonly)			BOOL		dialupConnect;		// ダイアルアップ接続
@property(readonly)			BOOL		supportsAttachment;	// ファイル添付サポート
@property(readonly)			BOOL		supportsEncrypt;	// 暗号化サポート
@property(readonly)			BOOL		supportsUTF8;		// UTF-8サポート
@property(readonly)			NSString*	summaryString;		// 表示用文字列

// ファクトリ
+ (id)userWithUserName:(NSString*)user
			 groupName:(NSString*)group
			  hostName:(NSString*)host
			 logOnName:(NSString*)logOn
			   address:(struct sockaddr_in*)addr
			   command:(UInt32)cmd;

+ (id)userWithHostList:(NSArray*)itemArray fromIndex:(unsigned)index;

// 初期化
- (id)initWithUserName:(NSString*)user
			 groupName:(NSString*)group
			  hostName:(NSString*)host
			 logOnName:(NSString*)logOn
			   address:(struct sockaddr_in*)addr
			   command:(UInt32)cmd;

- (id)initWithHostList:(NSArray*)itemArray fromIndex:(unsigned)index;

@end
