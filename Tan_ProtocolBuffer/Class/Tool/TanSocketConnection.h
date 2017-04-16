//
//  TanSocketConnection.h
//  Tan_ProtocolBuffer
//
//  Created by PX_Mac on 2017/4/15.
//  Copyright © 2017年 mac001. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ChatMsg;   //自定义Protobuf模型类

@interface TanSocketConnection : NSObject
    
+ (instancetype)manager;  //获取实例对象
    
@property (nonatomic, assign, readonly) BOOL isConnected; //IM通道是否连接中

/** 建立连接 */
- (void)connectCompletion:(void(^)(BOOL finish))completion;

/** 断开连接 */
- (void)disconnect;

/** 给服务端发送消息 */
- (void)sendMessage:(ChatMsg *)msg;

@end
