//
//  TanSocketConnection.m
//  Tan_ProtocolBuffer
//
//  Created by PX_Mac on 2017/4/15.
//  Copyright © 2017年 mac001. All rights reserved.
//

#import "TanSocketConnection.h"
#import "GCDAsyncSocket.h"
#import "CommonShop.pbobjc.h"   //自定义ProtoBuf 模型类头文件

#define kIMHost @"192.168.1.197"
#define kIMPort 5188

#define kIMHeartTag     6868

@interface TanSocketConnection () <GCDAsyncSocketDelegate>
{
    GCDAsyncSocket *_asyncSocket;
}

//接收服务器发过来的的data
@property (nonatomic, strong) NSMutableData *receiveData;

@end

@implementation TanSocketConnection
 
+ (instancetype)manager
{
    static TanSocketConnection *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[[self class] alloc] init];
    });
    return manager;
}

- (instancetype)init
{
    if (self = [super init]) {
        _asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    }
    return self;
}
    
/** 和服务端建立连接 */
- (void)connectCompletion:(void(^)(BOOL finish))completion{
    
    if (_asyncSocket.isConnected)
    {
        if (completion) completion(YES);
        return;
    }
    
    NSError *error = nil;
    [_asyncSocket connectToHost:kIMHost onPort:(UInt32)kIMPort withTimeout:120 error:&error];
    
    if (error) {
        if (completion) completion(NO);
    }
}
    
/** 断开socket连接 */
- (void)disconnect
{
    [_asyncSocket disconnect];
}
/** socket是否在连接中 */
- (BOOL)isConnected
{
    return [_asyncSocket isConnected];
}
    
/** 给服务端发送消息 */
- (void)sendMessage:(ChatMsg *)msg{
    NSData *data = [msg delimitedData]; //模型序列化
    [self writeData:data timeout:5*60 tag:kIMHeartTag];
}
    
#pragma mark GCDAsyncSocketDelegate method
/** 和服务器建立了连接后回调 */
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    //...
    [self runHeartbeat]; //发送心跳包
    //...
}

/** 监听来自服务器的消息，处理 */
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    [self.receiveData appendData:data];
    
    //读取data的头部占用字节 和 从头部读取内容长度
    //验证结果：数据比较小时头部占用字节为1，数据比较大时头部占用字节为2
    int32_t headL = 0;
    int32_t contentL = [self getContentLength:self.receiveData withHeadLength:&headL];
    
    if (contentL < 1){
        [sock readDataWithTimeout:-1 tag:0];
        return;
    }
    
    //拆包情况下：继续接收下一条消息，直至接收完这条消息所有的拆包，再解析
    if (headL + contentL > self.receiveData.length){
        [sock readDataWithTimeout:-1 tag:0];
        return;
    }
    
    //当receiveData长度不小于第一条消息内容长度时，开始解析receiveData
    [self parseContentDataWithHeadLength:headL withContentLength:contentL];
    [sock readDataWithTimeout:-1 tag:tag];
}  

/** 给服务器发送消息后回调 */
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag  
{
    //...
    [sock readDataWithTimeout:-1 tag:tag];  
}

/** 断开连接 */
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    //...
    [_asyncSocket disconnect];
    //...
}
    
    
#pragma mark - private methods
/** 解析二进制数据：NSData --> 自定义模型对象 */
- (void)parseContentDataWithHeadLength:(int32_t)headL withContentLength:(int32_t)contentL{
    
    NSRange range = NSMakeRange(0, headL + contentL);   //本次解析data的范围
    NSData *data = [self.receiveData subdataWithRange:range]; //本次解析的data
    
    GPBCodedInputStream *inputStream = [GPBCodedInputStream streamWithData:data];
    
    NSError *error;
    ChatMsg *obj = [ChatMsg parseDelimitedFromCodedInputStream:inputStream extensionRegistry:nil error:&error];
    
    if (!error){
        if (obj) [self saveReceiveInfo:obj];  //保存解析正确的模型对象
        [self.receiveData replaceBytesInRange:range withBytes:NULL length:0];  //移除已经解析过的data
    }
    
    if (self.receiveData.length < 1) return;
    
    //对于粘包情况下被合并的多条消息，循环递归直至解析完所有消息
    headL = 0;
    contentL = [self getContentLength:self.receiveData withHeadLength:&headL];
    
    if (headL + contentL > self.receiveData.length) return; //实际包不足解析，继续接收下一个包
    
    [self parseContentDataWithHeadLength:headL withContentLength:contentL]; //继续解析下一条
}

/** 获取data数据的内容长度和头部长度: index --> 头部占用长度 (头部占用长度1-4个字节) */
- (int32_t)getContentLength:(NSData *)data withHeadLength:(int32_t *)index{
    
    int8_t tmp = [self readRawByte:data headIndex:index];
    
    if (tmp >= 0) return tmp;
    
    int32_t result = tmp & 0x7f;
    if ((tmp = [self readRawByte:data headIndex:index]) >= 0) {
        result |= tmp << 7;
    } else {
        result |= (tmp & 0x7f) << 7;
        if ((tmp = [self readRawByte:data headIndex:index]) >= 0) {
            result |= tmp << 14;
        } else {
            result |= (tmp & 0x7f) << 14;
            if ((tmp = [self readRawByte:data headIndex:index]) >= 0) {
                result |= tmp << 21;
            } else {
                result |= (tmp & 0x7f) << 21;
                result |= (tmp = [self readRawByte:data headIndex:index]) << 28;
                if (tmp < 0) {
                    for (int i = 0; i < 5; i++) {
                        if ([self readRawByte:data headIndex:index] >= 0) {
                            return result;
                        }
                    }
                    
                    result = -1;
                }
            }
        }
    }
    return result;
}

/** 读取字节 */
- (int8_t)readRawByte:(NSData *)data headIndex:(int32_t *)index{
    
    if (*index >= data.length) return -1;
    
    *index = *index + 1;
    
    return ((int8_t *)data.bytes)[*index - 1];
}

/** 处理解析出来的信息 */
- (void)saveReceiveInfo:(ChatMsg *)obj{
    //...
}

/** 创建时钟器 发送心跳包 */
- (void)runHeartbeat
{
    //......
}

- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    [_asyncSocket readDataWithTimeout:timeout tag:tag];
}

/** 给服务器发送数据 */
- (void)writeData:(NSData *)data timeout:(NSTimeInterval)timeout tag:(long)tag
{
    [_asyncSocket writeData:data withTimeout:timeout tag:tag];
}
    
/** 存储接收来自服务器的包 */
- (NSMutableData *)receiveData{
    if (_receiveData == nil){
        _receiveData = [[NSMutableData alloc] init];
    }
    return _receiveData;
}
    
- (void)dealloc
{
    _asyncSocket.delegate = nil;
    _asyncSocket = nil;
}

@end
