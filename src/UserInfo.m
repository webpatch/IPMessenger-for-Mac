/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: UserInfo.m
 *	Module		: ユーザ情報クラス
 *============================================================================*/

#import <Foundation/Foundation.h>

//#define IPMSG_LOG_TRC	0

#import "UserInfo.h"
#import "IPMessenger.h"
#import "RecvMessage.h"
#import "MessageCenter.h"
#import "Config.h"
#import "NSStringIPMessenger.h"
#import "DebugLog.h"

#include <netinet/in.h>
#include <arpa/inet.h>

NSString* const kIPMsgUserInfoUserNamePropertyIdentifier	= @"UserName";
NSString* const kIPMsgUserInfoGroupNamePropertyIdentifier	= @"GroupName";
NSString* const kIPMsgUserInfoHostNamePropertyIdentifier	= @"HostName";
NSString* const kIPMsgUserInfoLogOnNamePropertyIdentifier	= @"LogOnName";
NSString* const kIPMsgUserInfoVersionPropertyIdentifer		= @"Version";
NSString* const kIPMsgUserInfoIPAddressPropertyIdentifier	= @"IPAddress";

@interface UserInfo()
@property(copy,readwrite)	NSString*			userName;
@property(copy,readwrite)	NSString*			groupName;
@property(copy,readwrite)	NSString*			hostName;
@property(copy,readwrite)	NSString*			logOnName;
@property(readwrite)		struct sockaddr_in	address;
@property(copy,readwrite)	NSString*			ipAddress;
@property(readwrite)		UInt32				ipAddressNumber;
@property(readwrite)		UInt16				portNo;
@property(readwrite)		BOOL				inAbsence;
@property(readwrite)		BOOL				dialupConnect;
@property(readwrite)		BOOL				supportsAttachment;
@property(readwrite)		BOOL				supportsEncrypt;
@property(readwrite)		BOOL				supportsUTF8;
@end

// クラス実装
@implementation UserInfo

@synthesize userName			= _userName;
@synthesize groupName			= _groupName;
@synthesize hostName			= _hostName;
@synthesize logOnName			= _logOnName;
@synthesize address				= _address;
@synthesize ipAddress			= _ipAddress;
@synthesize ipAddressNumber		= _ipAddressNumber;
@synthesize portNo				= _portNo;
@synthesize version				= _version;
@synthesize inAbsence			= _absence;
@synthesize dialupConnect		= _dialup;
@synthesize supportsAttachment	= _attachment;
@synthesize supportsEncrypt		= _encrypt;
@synthesize supportsUTF8		= _UTF8;

/*============================================================================*
 * ファクトリ
 *============================================================================*/

+ (id)userWithUserName:(NSString*)user
			 groupName:(NSString*)group
			  hostName:(NSString*)host
			 logOnName:(NSString*)logOn
			   address:(struct sockaddr_in*)addr
			   command:(UInt32)cmd
{
	return [[[UserInfo alloc] initWithUserName:user
									 groupName:group
									  hostName:host
									 logOnName:logOn
									   address:addr
									   command:cmd] autorelease];
}

+ (id)userWithHostList:(NSArray*)itemArray fromIndex:(unsigned)index
{
	return [[[UserInfo alloc] initWithHostList:itemArray fromIndex:index] autorelease];
}

/*============================================================================*
 * 初期化／解放
 *============================================================================*/

// 初期化
- (id)initWithUserName:(NSString*)user
			 groupName:(NSString*)group
			  hostName:(NSString*)host
			 logOnName:(NSString*)logOn
			   address:(struct sockaddr_in*)addr
			   command:(UInt32)cmd
{
	self = [super init];
	if (self) {
		self.userName			= user;
		self.groupName			= group;
		self.hostName			= host;
		self.logOnName			= logOn;
		self.address			= *addr;
		self.ipAddress			= [NSString stringWithUTF8String:inet_ntoa(self.address.sin_addr)];
		self.ipAddressNumber	= ntohl(self.address.sin_addr.s_addr);
		self.portNo				= ntohs(self.address.sin_port);
		self.version			= nil;
		self.inAbsence			= (BOOL)((cmd & IPMSG_ABSENCEOPT) != 0);
		self.dialupConnect		= (BOOL)((cmd & IPMSG_DIALUPOPT) != 0);
		self.supportsAttachment	= (BOOL)((cmd & IPMSG_FILEATTACHOPT) != 0);
		self.supportsEncrypt	= (BOOL)((cmd & IPMSG_ENCRYPTOPT) != 0);
		self.supportsUTF8		= (BOOL)((cmd & IPMSG_CAPUTF8OPT) != 0);
	}
	return self;
}

// 初期化（ホストリスト）
- (id)initWithHostList:(NSArray*)itemArray fromIndex:(unsigned)index
{
	self = [super init];
	if (self) {
		UInt32		command	= (UInt32)[[itemArray objectAtIndex:index + 1] intValue];
		NSString*	addrStr	= [itemArray objectAtIndex:index + 3];
		UInt32		addrNum	= (UInt32)inet_addr([addrStr UTF8String]);
		UInt16		port	= (UInt16)[[itemArray objectAtIndex:index + 4] intValue];

		struct sockaddr_in addr;
		addr.sin_family			= AF_INET;
		addr.sin_addr.s_addr	= addrNum;
		addr.sin_port			= port;

		self.userName			= [itemArray objectAtIndex:index + 5];
		self.groupName			= [itemArray objectAtIndex:index + 6];
		self.hostName			= [itemArray objectAtIndex:index + 1];
		self.logOnName			= [itemArray objectAtIndex:index];
		self.address			= addr;
		self.ipAddress			= addrStr;
		self.ipAddressNumber	= ntohl(addrNum);
		self.portNo				= ntohs(port);
		self.version			= nil;
		self.inAbsence			= (BOOL)((command & IPMSG_ABSENCEOPT) != 0);
		self.dialupConnect		= (BOOL)((command & IPMSG_DIALUPOPT) != 0);
		self.supportsAttachment	= (BOOL)((command & IPMSG_FILEATTACHOPT) != 0);
		self.supportsEncrypt	= (BOOL)((command & IPMSG_ENCRYPTOPT) != 0);
		self.supportsUTF8		= (BOOL)((command & IPMSG_CAPUTF8OPT) != 0);

		if ([self.userName isEqualToString:@"\b"]) {
			self.userName = nil;
		}
		if ([self.groupName isEqualToString:@"\b"]) {
			self.groupName = nil;
		}
	}

	return self;
}

// 解放
- (void)dealloc
{
	[_userName release];
	[_groupName release];
	[_hostName release];
	[_logOnName release];
	[_ipAddress release];
	[_version release];
	[super dealloc];
}

/*============================================================================*
 * メソッド
 *============================================================================*/

// 表示文字列
- (NSString*)summaryString
{
	NSMutableString* desc = [NSMutableString string];

	// ユーザ名
	if ([self.userName length] > 0) {
		[desc appendString:self.userName];
		// ログオン名
//		[desc appendString:@"["];
//		[desc appendString:logOnUser];
//		[desc appendString:@"]"];
	} else {
		[desc appendString:self.logOnName];
	}

	// 不在マーク
	if (self.inAbsence) {
		[desc appendString:@"*"];
	}

	[desc appendString:@" ("];

	// グループ名
	if ([self.groupName length] > 0) {
		[desc appendFormat:@"%@/", self.groupName];
	}

	// マシン名
	[desc appendString:self.hostName];

	// IPアドレス
//	[desc appendString:@"/"];
//	[desc appendString:address];

	[desc appendString:@")"];

	return desc;
}

/*============================================================================*
 * その他
 *============================================================================*/

// KVC
- (id)valueForKey:(NSString *)key
{
	if ([key isEqualToString:kIPMsgUserInfoUserNamePropertyIdentifier]) {
		return self.userName;
	} else if ([key isEqualToString:kIPMsgUserInfoGroupNamePropertyIdentifier]) {
		return self.groupName;
	} else if ([key isEqualToString:kIPMsgUserInfoHostNamePropertyIdentifier]) {
		return self.hostName;
	} else if ([key isEqualToString:kIPMsgUserInfoIPAddressPropertyIdentifier]) {
		return self.ipAddress;
	} else if ([key isEqualToString:kIPMsgUserInfoLogOnNamePropertyIdentifier]) {
		return self.logOnName;
	} else if ([key isEqualToString:kIPMsgUserInfoVersionPropertyIdentifer]) {
		return self.version;
	}
	return @"";
}

// 等価判定
- (BOOL)isEqual:(id)anObject
{
	if ([anObject isKindOfClass:[self class]]) {
		UserInfo* target = anObject;
		return ([self.logOnName isEqualToString:target.logOnName] &&
				(self.ipAddressNumber == target.ipAddressNumber) &&
				(self.portNo == target.portNo));
	}
	return NO;
}

// オブジェクト文字列表現
- (NSString*)description
{
	return [NSString stringWithFormat:@"%@@%@:%d", self.logOnName, self.hostName, self.portNo];
}

// コピー処理 （NSCopyingプロトコル）
- (id)copyWithZone:(NSZone*)zone
{
	UserInfo* newObj = [[UserInfo allocWithZone:zone] init];
	if (newObj) {
		newObj->_userName			= [self->_userName copyWithZone:zone];
		newObj->_groupName			= [self->_groupName copyWithZone:zone];
		newObj->_hostName			= [self->_hostName copyWithZone:zone];
		newObj->_logOnName			= [self->_logOnName copyWithZone:zone];
		newObj->_ipAddress			= [self->_ipAddress copyWithZone:zone];
		newObj->_ipAddressNumber	= self->_ipAddressNumber;
		newObj->_portNo				= self->_portNo;
		newObj->_version			= [self->_version copyWithZone:zone];
		newObj->_absence			= self->_absence;
		newObj->_dialup				= self->_dialup;
		newObj->_attachment			= self->_attachment;
		newObj->_encrypt			= self->_encrypt;
		newObj->_UTF8				= self->_UTF8;
	}
	return newObj;
}

@end
