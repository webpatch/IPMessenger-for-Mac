/*============================================================================*
 * (C) 2001-2014 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: AttachmentClient.m
 *	Module		: 添付ファイルダウンローダクラス
 *============================================================================*/

#import "AttachmentClient.h"
#import "Attachment.h"
#import "AttachmentFile.h"
#import "UserInfo.h"
#import "RecvMessage.h"
#import "Config.h"
#import "MessageCenter.h"
#import "NSStringIPMessenger.h"
#import "DebugLog.h"

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/socket.h>

/*============================================================================*
 * プライベートメソッド定義
 *============================================================================*/

@interface AttachmentClient(Private)
- (void)downloadThread:(id)param;
- (DownloadResult)downloadFile:(AttachmentFile*)file from:(int)sock;
- (DownloadResult)downloadDir:(AttachmentFile*)file from:(int)sock useUTF8:(BOOL)utf8;
- (DownloadResult)receiveFrom:(int)sock to:(void*)ptr maxLength:(unsigned)len;
- (void)incrementNumberOfFile;
- (void)incrementNumberOfDirectory;
- (void)newFileDownloadStart:(NSString*)fileName;
- (void)newDataDownload:(unsigned)size;
@end

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation AttachmentClient

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (id)initWithRecvMessage:(RecvMessage*)msg saveTo:(NSString*)path {
	self 			= [super init];
	listener		= nil;
	message			= [msg retain];
	stop			= NO;
	targets			= [[NSMutableArray alloc] init];
	lock			= [[NSLock alloc] init];
	savePath		= [path copy];
	startDate		= nil;
	numberOfFile	= 0;
	numberOfDir		= 0;
	indexOfTarget	= 0;
	currentFile		= @"";
	totalSize		= 0;
	downloadSize	= 0;
	percentage		= 0;

	return self;
}

// 解放
- (void)dealloc {
	[message release];
	[targets release];
	[lock release];
	[startDate release];
	[savePath release];
	[connection release];
	[super dealloc];
}

/*----------------------------------------------------------------------------*
 * 対象添付ファイル管理
 *----------------------------------------------------------------------------*/

// ファイル数
- (unsigned)numberOfTargets {
	return [targets count];
}

// 追加
- (void)addTarget:(Attachment*)attachment {
	if ([lock tryLock]) {
		[targets addObject:attachment];
		totalSize += [attachment file].size;
		[lock unlock];
	} else {
		WRN(@"try lock err.");
	}
}

/*----------------------------------------------------------------------------*
 * ダウンロード制御
 *----------------------------------------------------------------------------*/

// ダウンロード開始
- (void)startDownload:(id<AttachmentClientListener>)obj {
	if ([lock tryLock]) {
		NSPort*		port1 = [NSPort port];
		NSPort*		port2 = [NSPort port];
		NSArray*	array = [NSArray arrayWithObjects:port2, port1, nil];
		connection	= [[NSConnection alloc] initWithReceivePort:port1 sendPort:port2];
		stop		= NO;
		[connection setRootObject:obj];
		[NSThread detachNewThreadSelector:@selector(downloadThread:) toTarget:self withObject:array];
	} else {
		WRN(@"try lock err.");
	}
}

// ダウンロード停止
- (void)stopDownload {
	stop = YES;
}

/*----------------------------------------------------------------------------*
 * getter
 *----------------------------------------------------------------------------*/

- (unsigned)indexOfTarget {
	return indexOfTarget;
}

- (NSString*)currentFile {
	return currentFile;
}

- (unsigned)numberOfFile {
	return numberOfFile;
}

- (unsigned)numberOfDirectory {
	return numberOfDir;
}

- (unsigned long long)totalSize {
	return totalSize;
}

- (unsigned long long)downloadSize {
	return downloadSize;
}

- (unsigned)percentage {
	return percentage;
}

- (unsigned)averageSpeed {
	NSTimeInterval interval;
	if (!startDate) {
		return 0;
	}
	if (downloadSize == 0) {
		return 0;
	}
	interval = -[startDate timeIntervalSinceNow];
	if (interval == 0) {
		return 0;
	}
	return (unsigned)(downloadSize / interval);
}

/*----------------------------------------------------------------------------*
 * 内部用（Private）
 *----------------------------------------------------------------------------*/

// 添付ダウンロードスレッド
- (void)downloadThread:(id)portArray {
	NSAutoreleasePool*	pool	= [[NSAutoreleasePool alloc] init];
	int					num 	= [targets count];
	DownloadResult		result	= DL_SUCCESS;
	NSConnection*		conn	= [[NSConnection alloc] initWithReceivePort:[portArray objectAtIndex:0]
																   sendPort:[portArray objectAtIndex:1]];
	listener = [conn rootProxy];
	[listener setProtocolForProxy:@protocol(AttachmentClientListener)];

	DBG(@"start download thread.");

	// ステータス管理開始
	[startDate release];
	startDate		= [[NSDate alloc] init];
	numberOfFile	= 0;
	numberOfDir		= 0;
	currentFile		= nil;
	downloadSize	= 0;
	percentage		= 0;
	[listener downloadWillStart];
	// 添付毎ダウンロードループ
	for (indexOfTarget = 0; ((indexOfTarget < num) && !stop); indexOfTarget++) {
		int					sock;
		struct sockaddr_in	addr;
		Attachment* 		attach = [targets objectAtIndex:indexOfTarget];
		char				buf[256];

		if (!attach) {
			ERR(@"internal error(attach is nil,index=%d)", indexOfTarget);
			result = DL_INTERNAL_ERROR;
			break;
		}

		[listener downloadIndexOfTargetChanged];

		// ソケット準備
		sock = socket(AF_INET, SOCK_STREAM, 0);
		if (sock == -1) {
			ERR(@"socket open error");
			result = DL_SOCKET_ERROR;
			break;
		}

		// 接続
		memset(&addr, 0, sizeof(addr));
		addr.sin_family			= AF_INET;
		addr.sin_port			= htons([[MessageCenter sharedCenter] myPortNo]);
		addr.sin_addr.s_addr	= htonl([message fromUser].ipAddressNumber);
		if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
			ERR(@"connect error");
			close(sock);
			result = DL_CONNECT_ERROR;
			break;
		}
		/*
		if (fcntl(sock, F_SETFL, O_NONBLOCK) == -1) {
			ERR(@"socket option set error(errorno=%d)", errno);
			result = DL_SOCKET_ERROR;
			break;
		}
		*/

		// リクエスト送信
		UInt32	command = [attach.file isRegularFile] ? IPMSG_GETFILEDATA : IPMSG_GETDIRFILES;
		BOOL	utf8	= (BOOL)(([message command] & IPMSG_UTF8OPT) != 0);

		if (utf8) {
			command |= IPMSG_UTF8OPT;
		}
		sprintf(buf, "%d:%ld:%s:%s:%ld:%x:%x:%x:",
						IPMSG_VERSION,
						[MessageCenter nextMessageID],
						[NSUserName() SJISString],
						[[[MessageCenter sharedCenter] myHostName] SJISString],
						command,
						message.packetNo,
						[[attach fileID] intValue],
						0U);
		// リクエスト送信
		if (send(sock, buf, strlen(buf) + 1, 0) < 0) {
			ERR(@"file:attach request send error.(%s)", buf);
			close(sock);
			result = DL_COMMUNICATION_ERROR;
			break;
		}
//		DBG(@"send file/dir request=%s", buf);

		// ファイルダウンロード
		if ([[attach file] isRegularFile]) {
			result = [self downloadFile:attach.file from:sock];
			if (result == DL_SUCCESS) {
				attach.isDownloaded = YES;
			} else {
				ERR(@"download file error.(%@)", attach.file.name);
				close(sock);
				break;
			}
			[self incrementNumberOfFile];
		}
		// ディレクトリダウンロード
		else if ([[attach file] isDirectory]) {
			result = [self downloadDir:attach.file from:sock useUTF8:utf8];
			if (result == DL_SUCCESS) {
				attach.isDownloaded = YES;
			} else {
				ERR(@"download dir error.(%@)", attach.file.name);
				close(sock);
				break;
			}
			[self incrementNumberOfDirectory];
		}
		// リソースフォーク（未実装）
		// その他（未サポート）
		else {
			ERR(@"unsupported file type(%@)", attach.file.path);
		}

		// ソケットクローズ
		close(sock);
	}
	if (stop) {
		result = DL_STOP;
	}
	[listener downloadDidFinished:result];
	[lock unlock];
	DBG(@"stop download thread.");
	[pool release];
}


/*----------------------------------------------------------------------------*
 * ファイルダウンロード処理
 *----------------------------------------------------------------------------*/
- (DownloadResult)downloadFile:(AttachmentFile*)file from:(int)sock {

	char buf[8192];						// バッファサイズを変更可能に？
	unsigned long long	remain;
	unsigned			size;
	DownloadResult		ret;

	[self newFileDownloadStart:[file name]];
	// 保存先ディレクトリ指定
	[file setDirectory:savePath];
	DBG(@"file:start download file(%@)", [file name]);

	/*------------------------------------------------------------------------*
	 * データ受信
	 *------------------------------------------------------------------------*/

	// ファイルオープン／作成
	if (![file openFileForWrite]) {
		ERR(@"file:open/create file error(%@)", file.path);
		return DL_FILE_OPEN_ERROR;
	}
	// ファイル受信
	remain = file.size;
	while (remain > 0) {
		size = MIN(sizeof(buf), remain);
		ret = [self receiveFrom:sock to:buf maxLength:size];
		if ((ret != DL_SUCCESS) && (ret != DL_STOP)) {
			WRN(@"file:file receive error(%d,%@)", ret, [file name]);
			// ファイルクローズ
			[file closeFile];
			// 書きかけのファイルを削除
			[[NSFileManager defaultManager] removeItemAtPath:file.path error:NULL];
			return ret;
		}
		[self newDataDownload:size];
		remain -= size;						// 残りサイズ更新
		[file writeData:buf length:size];	// ファイル書き込み
	}

	// ファイルクローズ
	[file closeFile];

	return DL_SUCCESS;
}

/*----------------------------------------------------------------------------*
 * ディレクトリダウンロード処理
 *----------------------------------------------------------------------------*/
- (DownloadResult)downloadDir:(AttachmentFile*)dir from:(int)sock useUTF8:(BOOL)utf8
{
	char				buf[8192];		// バッファサイズを変更可能に？
	long				headerSize;
	NSString*			currentDir	= savePath;
	DownloadResult		result		= DL_SUCCESS;
	AttachmentFile*		file;
	unsigned long long	remain;
	DBG(@"dir:start download directory(%@)", [dir name]);

	/*------------------------------------------------------------------------*
	 * 各ファイル受信ループ
	 *------------------------------------------------------------------------*/
	while (!stop) {
		// ヘッダサイズ受信
		result = [self receiveFrom:sock to:buf maxLength:5];
		if (result != DL_SUCCESS) {
			ERR(@"dir:headerSize receive error(ret=%d)", result);
			break;
		}
		buf[4] = '\0';
		headerSize = strtol(buf, NULL, 16);
		if (headerSize == 0) {
			DBG(@"dir:download complete1(%@)", savePath);
			break;
		} else if (headerSize < 0) {
			ERR(@"dir:download internal error(headerSize=%ld,buf=%s)", headerSize, buf);
			result = DL_INVALID_DATA;
			break;
		} else if (headerSize >= sizeof(buf)) {
			ERR(@"dir:headerSize overflow(%ld,max=%lu)", headerSize, sizeof(buf));
			result = DL_INTERNAL_ERROR;
			break;
		}
		headerSize -= 5;	// 先頭のヘッダ長サイズ（"0000:"）分減らす
		if (headerSize == 0) {
			WRN(@"dir:headerSize is 0. why?");
			continue;
		}

		// ヘッダ受信
		result = [self receiveFrom:sock to:buf maxLength:headerSize];
		if (result != DL_SUCCESS) {
			ERR(@"dir:header receive error(ret=%d,size=%ld)", result, headerSize);
			break;
		}
		buf[headerSize] = '\0';
		NSString* header;
		if (utf8) {
			header = [NSString stringWithUTF8String:buf];
		} else {
			header = [NSString stringWithSJISString:buf];
		}
//		DBG(@"dir:recv Header=%s", buf);
		file = [AttachmentFile fileWithDirectory:currentDir header:header];
		if (!file) {
			ERR(@"dir:parse dir header error(%s)", buf);
			result = DL_INVALID_DATA;
			break;
		}

		// ファイルオープン／作成
		if (![file openFileForWrite]) {
			ERR(@"dir:open/create file error(%@)", file.path);
			result = DL_FILE_OPEN_ERROR;
			break;
		}
		// ディレクトリ移動
		if ([file isRegularFile]) {
			[self newFileDownloadStart:[file name]];
		} else if ([file isDirectory]) {
			[self newFileDownloadStart:[file name]];
			currentDir = file.path;
			DBG(@"dir:chdir to child (-> \"%@\")", [currentDir substringFromIndex:[savePath length] + 1]);
		} else if ([file isParentDirectory]) {
			currentDir = file.path;
			DBG(@"dir:chdir to parent(<- \"%@\")",
					([currentDir length] > [savePath length]) ? [currentDir substringFromIndex:[savePath length] + 1] : @"");
		}
		// ファイル受信
		remain = file.size;
		if (remain > 0) {
			totalSize += remain;
			[listener downloadTotalSizeChanged];
			while (remain > 0) {
				unsigned size = MIN(sizeof(buf), remain);
				result = [self receiveFrom:sock to:buf maxLength:size];
				if (result != DL_SUCCESS) {
					ERR(@"dir:file receive error(%d,remain=%llu)", result, remain);
					break;
				}
				[self newDataDownload:size];
				remain -= size;						// 残りサイズ更新
				[file writeData:buf length:size];	// ファイル書き込み
			}
		}
		// ファイルクローズ
		[file closeFile];

		if (result != DL_SUCCESS) {
			// エラー発生
			break;
		}
		if (remain > 0) {
			// 受信しきれていない（エラー）
			ERR(@"dir:file remain data exist(%llu)", remain);
			result = DL_SIZE_NOT_ENOUGH;
			break;
		}

		if ([file isRegularFile]) {
			[self incrementNumberOfFile];
		} else if ([file isParentDirectory]) {
			[self incrementNumberOfDirectory];
		}

		// 終了判定
		if ([currentDir isEqualToString:savePath]) {
			DBG(@"dir:download complete2(%@)", savePath);
			break;
		}
	}

	// エラー判定
	if (stop) {
		// 停止された場合
		result = DL_STOP;
	}
/* 大量のダウンロード済みファイルを削除するとかなり重くなるので、やめておく
	if ((result != DL_SUCCESS) && (result != DL_STOP)) {
		// エラーの場合削除（ユーザの停止は除く）
		NSString* dir = [savePath stringByAppendingPathComponent:[file name]];
		DBG(@"dir:rmdir because of stop or error.(%@)", dir);
		[[NSFileManager defaultManager] removeFileAtPath:dir handler:nil];
	}
*/

	return result;
}

// ソケット受信
- (DownloadResult)receiveFrom:(int)sock to:(void*)ptr maxLength:(unsigned)len {

	int				timeout	= 0;	// タイムアウト回数
	fd_set			fdSet;			// ソケット監視用
	struct timeval	tv;				// ソケット監視用
	unsigned		recvSize = 0;	// 受信データサイズ
	int				ret;
	int				size;
	for (timeout = 0; (timeout < 40) && !stop; timeout++) {
		if (stop) {
			WRN(@"user cancel(stop)");
			return DL_STOP;
		}
		FD_ZERO(&fdSet);
		FD_SET(sock, &fdSet);
		tv.tv_sec	= 0;
		tv.tv_usec	= 500000;
		// ソケット監視
		ret = select(sock + 1, &fdSet, NULL, NULL, &tv);
		if (ret == 0) {
			// 受信なし
			DBG(@"timeout(sock=%d,count=%d)", sock, timeout);
			continue;
		}
		if (ret < 0) {
			// 受信エラー
			ERR(@"socket error(select).");
			return DL_SOCKET_ERROR;
		}
		// 正常受信
		timeout = -1;
		size = recv(sock, &(((char*)ptr)[recvSize]), len - recvSize, 0);
		if (size < 0) {
			ERR(@"socket error(recv=%d,maybe disconnected.)", size);
			return DL_DISCONNECTED;
		}
		recvSize += size;
		if (recvSize < len) {
			continue;
		}

		return DL_SUCCESS;
	}

	WRN(@"receive timeout(%dsec,sock=%d)", timeout/2, sock);

	return DL_TIMEOUT;
}

/*----------------------------------------------------------------------------*
 * ファイル状態変化
 *----------------------------------------------------------------------------*/

- (void)incrementNumberOfFile {
	numberOfFile++;
	[listener downloadNumberOfFileChanged];
}

- (void)incrementNumberOfDirectory {
	numberOfDir++;
	[listener downloadNumberOfDirectoryChanged];
}

- (void)newFileDownloadStart:(NSString*)fileName {
	currentFile = fileName;
	[listener downloadFileChanged];
}

- (void)newDataDownload:(unsigned)size {
	if (size > 0) {
		downloadSize += size;
		[listener downloadDownloadedSizeChanged];
		if (totalSize > 0) {
			unsigned newPer = ((float)downloadSize / (float)totalSize) * 100 + 0.5;
			if (newPer != percentage) {
				percentage = newPer;
				[listener downloadPercentageChanged];
			}
		}
	}
}

@end
