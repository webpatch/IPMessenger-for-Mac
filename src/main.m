/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: main.m
 *	Module		: アプリケーションエントリポイント
 *	Description	: アプリケーションメイン関数（ProjectBuilderによる自動生成）
 *============================================================================*/

#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[])
{
	signal(SIGPIPE, SIG_IGN);	// 添付ファイルクライアントからの切断時サーバクラッシュを避けるため
	return NSApplicationMain(argc, argv);
}
