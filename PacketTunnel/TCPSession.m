//
//  TCPSession.m
//  PacketProcessing
//
//  Created by HWG on 2017/5/20.
//  Copyright © 2017年 HWG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TCPSession.h"
#import "GCDAsyncSocket.h"
#import "IPv4Header.h"
#import "TCPHeader.h"
#import "SessionManager.h"
#import "TCPPacketFactory.h"
@interface TCPSession () <GCDAsyncSocketDelegate>
@property (nonatomic) GCDAsyncSocket* tcpSocket;
@end

@implementation TCPSession
-(instancetype)init:(NSString*)ip port:(uint16_t)port srcIp:(NSString*)srcIp srcPort:(uint16_t)srcPort{
    //NSString* key=[NSString stringWithFormat:@"%@:%d-%@:%d",srcIp,srcPort,ip,port];
    self.destIP=ip;
    self.destPort=port;
    self.sourceIP=srcIp;
    self.sourcePort=srcPort;
    NSError* error=nil;
    //self.tcpSocket=[[GCDAsyncSocket alloc]initWithDelegate:self delegateQueue:[SessionManager sharedInstance].globalQueue];
    self.tcpSocket=[[GCDAsyncSocket alloc]initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    //[[SessionManager sharedInstance].wormhole passMessageObject:@"Before Connect" identifier:@"VPNStatus"];
    [self.tcpSocket connectToHost:ip onPort:port error:&error];
    if(error!=nil){
        [[SessionManager sharedInstance].wormhole passMessageObject:error identifier:@"VPNStatus"];
    }
    //[[SessionManager sharedInstance].wormhole passMessageObject:@"After Connect" identifier:@"VPNStatus"];
    self.connected=[self.tcpSocket isConnected];
    self.syncSendAmount=[[NSObject alloc]init];
    self.recSequence=0;
    self.sendUnack=0;
    self.isacked=false;
    self.sendNext=0;
    self.sendWindow=0;
    self.sendWindowSize=0;
    self.sendWindowScale=0;
    self.sendAmountSinceLastAck=0;
    self.maxSegmentSize=0;
    self.connected=false;
    self.closingConnection=false;
    self.packetCorrupted=false;
    self.ackedToFin=false;
    self.abortingConnection=false;
    self.hasReceivedLastSegment=false;
    self.isDataForSendingReady=false;
    self.lastIPheader=nil;
    self.lastTCPheader=nil;
    self.timestampSender=0;
    self.timestampReplyto=0;
    self.unackData=[[NSMutableData alloc]init];
    self.resendPacketCounter=0;
    self.count=0;
    return self;
}

-(void)write:(NSData*)data{
    [self.tcpSocket writeData:data withTimeout:-1 tag:0];
}

-(void)close{
    [self.tcpSocket disconnect];
}

-(void)decreaseAmountSentSinceLastAck:(int)amount{
    @synchronized (self.syncSendAmount) {
        self.sendAmountSinceLastAck-=amount;
        if(self.sendAmountSinceLastAck<0){
            self.sendAmountSinceLastAck=0;
        }
    }
}

-(bool)isClientWindowFull{
    bool yes=false;
    //[[SessionManager sharedInstance].dict setObject:@"" forKey:[NSString stringWithFormat:@"%@:%d",@"sendwindow",self.sendWindow]];
    //[[SessionManager sharedInstance].dict setObject:@"" forKey:[NSString stringWithFormat:@"%@:%d",@"sendAmount",self.sendAmountSinceLastAck]];
    if(self.sendWindow>0&&self.sendAmountSinceLastAck>=0){
        yes=true;
    }else if(self.sendWindow==0&&self.sendAmountSinceLastAck>65535){
        yes=true;
    }
    return yes;
}

-(void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port{

    [[SessionManager sharedInstance].wormhole passMessageObject:@"TCPSession Connected" identifier:@"VPNStatus"];

    self.connected=true;
    /*
    NSMutableDictionary *sslSettings = [[NSMutableDictionary alloc] init];
    NSData *pkcs12data = [[NSData alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"client" ofType:@"p12"]];
    CFDataRef inPKCS12Data = (CFDataRef)CFBridgingRetain(pkcs12data);
    CFStringRef password = CFSTR("YOUR PASSWORD");
    const void *keys[] = { kSecImportExportPassphrase };
    const void *values[] = { password };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    
    CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
    
    OSStatus securityError = SecPKCS12Import(inPKCS12Data, options, &items);
    CFRelease(options);
    CFRelease(password);
    
    if(securityError == errSecSuccess)
        NSLog(@"Success opening p12 certificate.");
    
    CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
    SecIdentityRef myIdent = (SecIdentityRef)CFDictionaryGetValue(identityDict,
                                                                  kSecImportItemIdentity);
    
    SecIdentityRef  certArray[1] = { myIdent };
    CFArrayRef myCerts = CFArrayCreate(NULL, (void *)certArray, 1, NULL);
    
    [sslSettings setObject:(id)CFBridgingRelease(myCerts) forKey:(NSString *)kCFStreamSSLCertificates];
    [sslSettings setObject:NSStreamSocketSecurityLevelNegotiatedSSL forKey:(NSString *)kCFStreamSSLLevel];
    [sslSettings setObject:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamSSLAllowsAnyRoot];
    [sslSettings setObject:@"CONNECTION ADDRESS" forKey:(NSString *)kCFStreamSSLPeerName];
    [sock startTLS:sslSettings];
     */
    //NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:3];
    //允许自签名证书手动验证
    //[settings setObject:@YES forKey:GCDAsyncSocketManuallyEvaluateTrust];
    //GCDAsyncSocketSSLPeerName
    //[settings setObject:@"tv.diveinedu.com" forKey:GCDAsyncSocketSSLPeerName];
    
    // 如果不是自签名证书，而是那种权威证书颁发机构注册申请的证书
    // 那么这个settings字典可不传。
    
    //[sock startTLS:nil]; // 开始SSL握手
    
    [sock readDataWithTimeout:-1 tag:0];

}
-(void)socketDidSecure:(GCDAsyncSocket *)sock{
    [[SessionManager sharedInstance].wormhole passMessageObject:@"TCPSession Secure" identifier:@"VPNStatus"];
}

-(void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag{
    NSLog(@"DID WRITE");

    [[SessionManager sharedInstance].wormhole passMessageObject:@"TCPSocket DataSent" identifier:@"VPNStatus"];
    [[SessionManager sharedInstance].dict setObject:@"" forKey:[NSString stringWithFormat:@"%@:%@",self.destIP,@"Sent"]];

}
-(void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag{
    NSLog(@"DID READ");
    //if(!self.isClientWindowFull){
        [[SessionManager sharedInstance].wormhole passMessageObject:@"TCPSocket DataReceived" identifier:@"VPNStatus"];
        //[[SessionManager sharedInstance].dict setObject:data forKey:[NSString stringWithFormat:@"%@-%d:%d",self.destIP,self.count++,[data length]]];
    
    Byte* array=(Byte*)[data bytes];
    int flag=0;
    while(([data length]-flag)>1024){
        //[[SessionManager sharedInstance].dict setObject:data forKey:[NSString stringWithFormat:@"%@-%d:%d",self.destIP,self.count++,1024]];
        @autoreleasepool {

        NSMutableData* segment=[NSMutableData dataWithBytes:array+flag length:1024];
        flag+=1024;
        IPv4Header* ipheader=self.lastIPheader;
        TCPHeader* tcpheader=self.lastTCPheader;
        int unack=[self sendNext];
        int nextunack=unack+1024;
        [self setSendNext:nextunack];
        [self setUnackData:[NSMutableData dataWithData:segment]];
        [self setResendPacketCounter:0];
        NSMutableData* packetbody=[TCPPacketFactory createResponsePacketData:ipheader tcp:tcpheader packetdata:[NSMutableData dataWithData:segment] ispsh:true ackNumber:[self recSequence] seqNumber:unack timeSender:[self timestampSender] timeReplyto:[self timestampReplyto]];
        @synchronized ([SessionManager sharedInstance].packetFlow) {
            [[SessionManager sharedInstance].packetFlow writePackets:@[packetbody] withProtocols:@[@(AF_INET)]];
        }
        }
    }
    NSLog(@"DID PROCESS MAIN");

    if(([data length]-flag)>0){
        //[[SessionManager sharedInstance].dict setObject:data forKey:[NSString stringWithFormat:@"%@-%d:%d",self.destIP,self.count++,([data length]-flag)]];
        @autoreleasepool {

        NSMutableData* segment=[NSMutableData dataWithBytes:array+flag length:([data length]-flag)];
        IPv4Header* ipheader=self.lastIPheader;
        TCPHeader* tcpheader=self.lastTCPheader;
        int unack=[self sendNext];
        int nextunack=unack+([data length]-flag);
        [self setSendNext:nextunack];
        [self setUnackData:segment];
        [self setResendPacketCounter:0];
        
        NSMutableData* packetbody=[TCPPacketFactory createResponsePacketData:ipheader tcp:tcpheader packetdata:[NSMutableData dataWithData:segment] ispsh:true ackNumber:[self recSequence] seqNumber:unack timeSender:[self timestampSender] timeReplyto:[self timestampReplyto]];
        
        @synchronized ([SessionManager sharedInstance].packetFlow) {
            [[SessionManager sharedInstance].packetFlow writePackets:@[packetbody] withProtocols:@[@(AF_INET)]];
        }
            
        }
    }
    data=nil;
    NSLog(@"DID PROCESS TAIL");

    /*
        NSMutableData* buffer=[[NSMutableData alloc]init];
        [buffer appendData:data];
        IPv4Header* ipheader=self.lastIPheader;
        TCPHeader* tcpheader=self.lastTCPheader;
        int unack=[self sendNext];
        int nextunack=unack+[data length];
        [self setSendNext:nextunack];
        [self setUnackData:[NSMutableData dataWithData:data]];
        [self setResendPacketCounter:0];
        NSMutableData* packetbody=[TCPPacketFactory createResponsePacketData:ipheader tcp:tcpheader packetdata:[NSMutableData dataWithData:data] ispsh:true ackNumber:[self recSequence] seqNumber:unack timeSender:[self timestampSender] timeReplyto:[self timestampReplyto]];
    [[SessionManager sharedInstance].dict setObject:data forKey:[NSString stringWithFormat:@"%@-%d",self.destIP,[data length]]];
    [[SessionManager sharedInstance].dict setObject:packetbody forKey:[NSString stringWithFormat:@"%@-%d",self.destIP,[packetbody length]]];
        @synchronized ([SessionManager sharedInstance].packetFlow) {
            [[SessionManager sharedInstance].packetFlow writePackets:@[packetbody] withProtocols:@[@(AF_INET)]];
        }
     */
    [sock readDataWithTimeout:-1 tag:0];
}

-(void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err{
    //[self.tcpSocket disconnectAfterReadingAndWriting];
    [[SessionManager sharedInstance].wormhole passMessageObject:@"TCPSession Disconnected" identifier:@"VPNStatus"];
    [self setConnected:false];
    NSMutableData* rstarray=[TCPPacketFactory createRstData:self.lastIPheader tcpheader:self.lastTCPheader datalength:0];
    
    /*
    Byte array[[rstarray count]];
    for(int i=0;i<[rstarray count];i++){
        array[i]=(Byte)[rstarray[i] shortValue];
    }
    NSData* data=[NSData dataWithBytes:array length:[rstarray count]];
     */
    
    @synchronized ([SessionManager sharedInstance].packetFlow) {
        [[SessionManager sharedInstance].packetFlow writePackets:@[rstarray] withProtocols:@[@(AF_INET)]];
    }
    [self setAbortingConnection:true];
    [[SessionManager sharedInstance]closeSession:self];
}

-(void)sendToRequester:(NSMutableData*)buffer socket:(GCDAsyncSocket*)socket datasize:(int)datasize sess:(TCPSession*)sess{
    if(sess==nil){
        return;
    }
    if(datasize<65535){
        [sess setHasReceivedLastSegment:true];
    }else{
        [sess setHasReceivedLastSegment:false];
    }
}

-(void)pushDataToClient:(NSMutableData*)buffer session:(TCPSession*)session{
    IPv4Header* ipheader=self.lastIPheader;
    TCPHeader* tcpheader=self.lastTCPheader;
    int max=session.maxSegmentSize-60;
    if(max<1){
        max=1024;
    }
    int unack=session.sendNext;
    int nextUnack=self.sendNext+[buffer length];
    [session setSendNext:nextUnack];
    [session setUnackData:buffer];
    [session setResendPacketCounter:0];
    NSMutableData* data=[TCPPacketFactory createResponsePacketData:ipheader tcp:tcpheader packetdata:buffer ispsh:[session hasReceivedLastSegment] ackNumber:[session recSequence] seqNumber:unack timeSender:[session timestampSender] timeReplyto:[session timestampReplyto]];
    /*
    Byte array[[data count]];
    for(int i=0;i<[data count];i++){
        array[i]=(Byte)[data[i] shortValue];
    }
     */
    @synchronized ([SessionManager sharedInstance].packetFlow) {
        [[SessionManager sharedInstance].packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
    }
}

-(void)setSendingData:(NSData*)data{
    
}
@end


























