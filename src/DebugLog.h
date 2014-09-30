/*============================================================================*
 * (C) 2001-2011 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for Mac OS X
 *	File		: DebugLog.h
 *	Module		: デバッグログ機能
 *	Description	: デバッグログマクロ定義
 *============================================================================*/

#include <Foundation/Foundation.h>

/*============================================================================*
 * 出力フラグ
 *		IPMSG_DEBUGがメインスイッチ（定義がない場合全レベル強制OFF）
 *		※ Xcodeのビルドスタイルにて定義されている
 *			・Release ビルドスタイル：出力しない（定義なし）
 *			・Debug   ビルドスタイル：出力する（定義あり）
 *============================================================================*/

// レベル別出力フラグ
//		0:出力しない
//		1:出力する
#ifndef IPMSG_LOG_TRC
#define IPMSG_LOG_TRC	0
#endif

#ifndef IPMSG_LOG_DBG
#define IPMSG_LOG_DBG	1
#endif

#ifndef IPMSG_LOG_WRN
#define IPMSG_LOG_WRN	1
#endif

#ifndef IPMSG_LOG_ERR
#define IPMSG_LOG_ERR	1
#endif

/*============================================================================*
 * トレースレベルログ
 *============================================================================*/

#if defined(IPMSG_DEBUG) && (IPMSG_LOG_TRC == 1)
#define _LOG_TRC	@"T ",__FILE__,__LINE__,__FUNCTION__
#define TRC(...)	IPMsgLog(_LOG_TRC,[NSString stringWithFormat:__VA_ARGS__])
#else
#define TRC(...)
#endif

/*============================================================================*
 * デバッグレベルログ
 *============================================================================*/

#if defined(IPMSG_DEBUG) && (IPMSG_LOG_DBG == 1)
	#define _LOG_DBG	@"D ",__FILE__,__LINE__,__FUNCTION__
	#define DBG(...)	IPMsgLog(_LOG_DBG,[NSString stringWithFormat:__VA_ARGS__])
#else
	#define DBG(...)
#endif

/*============================================================================*
 * 警告レベルログ
 *============================================================================*/

#if defined(IPMSG_DEBUG) && (IPMSG_LOG_WRN == 1)
	#define _LOG_WRN	@"W-",__FILE__,__LINE__,__FUNCTION__
	#define WRN(...)	IPMsgLog(_LOG_WRN,[NSString stringWithFormat:__VA_ARGS__])
#else
	#define WRN(...)
#endif

/*============================================================================*
 * エラーレベルログ
 *============================================================================*/

#if defined(IPMSG_DEBUG) && (IPMSG_LOG_ERR == 1)
	#define _LOG_ERR	@"E*",__FILE__,__LINE__,__FUNCTION__
	#define ERR(...)	IPMsgLog(_LOG_ERR,[NSString stringWithFormat:__VA_ARGS__])
#else
	#define ERR(...)
#endif

/*============================================================================*
 * 関数プロトタイプ
 *============================================================================*/

#ifdef __cplusplus
extern "C" {
#endif

#if defined(IPMSG_DEBUG)
// ログ出力関数
void IPMsgLog(NSString* level, const char* file, int line, const char* func, NSString* msg);
#endif

#ifdef __cplusplus
}	// extern "C"
#endif
