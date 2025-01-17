//
//  EasePublishViewController.m
//
//  Created by EaseMob on 16/6/3.
//  Copyright © 2016年 zmw. All rights reserved.
//

#import "EasePublishViewController.h"

#import "SDImageCache.h"
#import "SDWebImageDownloader.h"
#import "EaseChatView.h"
#import "EaseHeartFlyView.h"
#import "EaseLiveHeaderListView.h"
#import "UIImage+Color.h"
#import "EaseProfileLiveView.h"
#import "EaseLiveCastView.h"
#import "EaseAdminView.h"
#import "EaseLiveRoom.h"
#import "EaseAnchorCardView.h"
#import "EaseCreateLiveViewController.h"
#import "EaseDefaultDataHelper.h"
#import "EaseAudienceBehaviorView.h"
#import "EaseGiftListView.h"
#import "EaseCustomMessageHelper.h"
#import "EaseFinishLiveView.h"
#import "EaseCustomMessageHelper.h"
#import "EaseLiveViewController.h"

#import <AgoraRtcKit/AgoraRtcEngineKit.h>

#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>

#import <CallKit/CXCallObserver.h>

#define kDefaultTop 35.f
#define kDefaultLeft 10.f

@interface EasePublishViewController ()
<
    EaseChatViewDelegate,
    UITextViewDelegate,
    EMChatroomManagerDelegate,
    TapBackgroundViewDelegate,
    EaseLiveHeaderListViewDelegate,
    EaseProfileLiveViewDelegate,
    UIAlertViewDelegate,
    EMClientDelegate,
    EaseCustomMessageHelperDelegate,
    AgoraDirectCdnStreamingEventDelegate,
    AgoraRtcEngineDelegate
>
{
    BOOL _isload;
    BOOL _isShutDown;
    
    UIView *_blackView;
    
    BOOL _isPublish;
    
    BOOL _isAllMute;
    
    BOOL _isFinishBroadcast;
        
    NSInteger _praiseNum;//赞
    NSInteger _giftsNum;//礼物份数
    NSInteger _totalGifts;//礼物合计总数
    
    EaseCustomMessageHelper *_customMsgHelper;//自定义消息帮助
    
    NSURL *_streamCloudURL;
    NSURL *_streamURL;
}

@property (nonatomic, strong) EaseLiveRoom *room;
@property (nonatomic, strong) EaseLiveHeaderListView *headerListView;
@property (nonatomic, strong) UILabel *roomNameLabel;
@property (nonatomic, strong) UIWindow *subWindow;

@property (strong, nonatomic) UITapGestureRecognizer *singleTapGR;

//聊天室
@property (strong, nonatomic) EaseChatView *chatview;
@property(nonatomic,strong) UIImageView *backImageView;

@property (nonatomic, strong) AgoraRtcEngineKit *agoraKit;
@property (nonatomic, strong) UIView *agoraLocalVideoView;

@property (nonatomic, strong) CTCallCenter *callCenter;

@end

@implementation EasePublishViewController

- (instancetype)initWithLiveRoom:(EaseLiveRoom*)room
{
    self = [super init];
    if (self) {
        _room = room;
        _customMsgHelper = [[EaseCustomMessageHelper alloc]initWithCustomMsgImp:self chatId:_room.chatroomId];
        _praiseNum = [EaseDefaultDataHelper.shared.praiseStatisticstCount intValue];
        _giftsNum = [EaseDefaultDataHelper.shared.giftNumbers intValue];
        _totalGifts = [EaseDefaultDataHelper.shared.totalGifts intValue];
        _isFinishBroadcast = NO;
        EaseDefaultDataHelper.shared.currentRoomId = _room.roomId;
        [EaseDefaultDataHelper.shared archive];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    //[self.view insertSubview:self.backImageView atIndex:0];
    [[EMClient sharedClient].roomManager addDelegate:self delegateQueue:nil];
    [[EMClient sharedClient] addDelegate:self delegateQueue:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    
    [self setupForDismissKeyboard];
    
    [self.view addSubview:self.headerListView];
    [self.view addSubview:self.chatview];
    [self.chatview joinChatroomWithIsCount:NO
                                completion:^(BOOL success) {
                                    if (success) {
                                        [self.headerListView loadHeaderListWithChatroomId:_room.chatroomId];
                                    }
                                }];
    [self.view layoutSubviews];
    [self setBtnStateInSel:0];
    if ([_room.liveroomType isEqualToString:kLiveBoardCastingTypeAGORA_CND_LIVE]) {
        //急速直播与互动直播均采用joinchannel方式直播
        [self setupdCDNAgoreKit];
    }else{
        [self setupChannelAgoreKit];
    }
}

- (void)dealloc
{
    /**
     @property (nonatomic, strong) NSString *praiseStatisticstCount;//点赞统计
     @property (nonatomic, strong) NSMutableDictionary *giftStatisticsCount;//礼物统计
     @property (nonatomic, strong) NSMutableArray *rewardCount;//打赏人列表
     @property (nonatomic, strong) NSString *giftNumbers;//礼物份数
     @property (nonatomic, strong) NSString *totalGifts;//礼物总数合计
     */
    [[EMClient sharedClient].roomManager removeDelegate:self];
    [[EMClient sharedClient] removeDelegate:self];
    [_headerListView stopTimer];
    _chatview.delegate = nil;
    
    EaseDefaultDataHelper.shared.praiseStatisticstCount = @"";
    [EaseDefaultDataHelper.shared.giftStatisticsCount removeAllObjects];
    [EaseDefaultDataHelper.shared.rewardCount removeAllObjects];
    EaseDefaultDataHelper.shared.giftNumbers = @"";
    EaseDefaultDataHelper.shared.totalGifts = @"";
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:false];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.chatview endEditing:YES];
}

//检测来电
- (void)monitorCall
{
    __weak typeof(self) weakSelf = self;
    self.callCenter.callEventHandler = ^(CTCall* call) {
        if (call.callState == CTCallStateDisconnected) {
            NSLog(@"电话结束或挂断电话");
            [weakSelf connectionStateDidChange:EMConnectionConnected];
        } else if (call.callState == CTCallStateConnected){
            NSLog(@"电话接通");
        } else if(call.callState == CTCallStateIncoming) {
            NSLog(@"来电话");
            [weakSelf.agoraKit muteLocalVideoStream:YES];
            [weakSelf.agoraKit muteLocalAudioStream:YES];
        } else if (call.callState ==CTCallStateDialing) {
            NSLog(@"拨号打电话(在应用内调用打电话功能)");
        }
    };
}
-(void)setupChannelAgoreKit{
    AgoraRtcEngineConfig *config = [[AgoraRtcEngineConfig alloc] init];
    config.appId = @"b79a23d7b1074ed9b0c756c63fd4fa81";
    config.channelProfile = AgoraChannelProfileLiveBroadcasting;
    self.agoraKit = [AgoraRtcEngineKit sharedEngineWithConfig:config delegate:self];
    [self _setupLocalVideo];
    [_agoraKit setChannelProfile:AgoraChannelProfileLiveBroadcasting];
    [_agoraKit setClientRole:AgoraClientRoleBroadcaster];
    __weak typeof(self) weakSelf = self;
    [self fetchAgoraRtcToken:^(NSString *rtcToken ,NSUInteger agoraUserId) {
        [weakSelf.agoraKit joinChannelByToken:rtcToken channelId:_room.channel info:nil uid:(NSUInteger)agoraUserId joinSuccess:^(NSString *channel, NSUInteger uid, NSInteger elapsed) {

        }];
    }];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
}
- (void)setupdCDNAgoreKit{
    
    AgoraRtcEngineConfig *config = [[AgoraRtcEngineConfig alloc] init];
    config.appId = @"b79a23d7b1074ed9b0c756c63fd4fa81";
    config.channelProfile = AgoraChannelProfileLiveBroadcasting;
    self.agoraKit = [AgoraRtcEngineKit sharedEngineWithConfig:config delegate:self];
    [_agoraKit setChannelProfile:AgoraChannelProfileLiveBroadcasting];
    [_agoraKit setClientRole:AgoraClientRoleBroadcaster];
    AgoraVideoEncoderConfiguration *videoConfig = [[AgoraVideoEncoderConfiguration alloc] initWithSize:CGSizeMake(640, 360)
                                                                                        frameRate:AgoraVideoFrameRateFps15
                                                                                          bitrate:700
                                                                                  orientationMode:AgoraVideoOutputOrientationModeFixedPortrait
                                                                                       mirrorMode:AgoraVideoMirrorModeDisabled];
    [_agoraKit setVideoEncoderConfiguration:videoConfig];
    [_agoraKit enableVideo];
    [self _setupLocalVideo];
    //融合cdn 和 互动直播都使用直推流方式
    [_agoraKit setDirectCdnStreamingAudioProfile:AgoraAudioProfileDefault];
    [_agoraKit setDirectCdnStreamingVideoConfiguration:videoConfig];
    AgoraDirectCdnStreamingMediaOptions *options = [[AgoraDirectCdnStreamingMediaOptions alloc] init];
    options.publishCameraTrack = [AgoraRtcBoolOptional of:true];
    options.publishMicrophoneTrack = [AgoraRtcBoolOptional of:true];

    __block typeof(options) blockOptions = options;
    __strong typeof(self) strongSelf = self;
    __weak typeof(self) weakSelf = self;
    NSDictionary *paramtars = @{
        @"domain":@"ws1-rtmp-push.easemob.com",
        @"pushPoint":@"live",
        @"streamKey":_room.channel ? _room.channel : _room.chatroomId,
        @"expire":@"3600"
    };
    [EaseHttpManager.sharedInstance getArgoLiveRoomPushStreamUrlParamtars:paramtars Completion:^(NSString *pushStreamStr) {
        NSInteger code = [weakSelf.agoraKit startDirectCdnStreaming:strongSelf publishUrl:pushStreamStr mediaOptions:blockOptions];
        [weakSelf.agoraKit enableAudio];
        [weakSelf.agoraKit setDefaultAudioRouteToSpeakerphone:true];
        if (code != 0) {
            
        }
        
    }];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
}

- (void)_setupLocalVideo {
    self.agoraLocalVideoView = [[UIView alloc]init];
    self.agoraLocalVideoView.frame = self.view.bounds;
    [self.view insertSubview:self.agoraLocalVideoView atIndex:0];
    
    AgoraRtcVideoCanvas *videoCanvas = [[AgoraRtcVideoCanvas alloc] init];
    videoCanvas.uid = 0;
    videoCanvas.view = self.agoraLocalVideoView;
    videoCanvas.renderMode = AgoraVideoRenderModeHidden;
    // 设置本地视图。
    [_agoraKit enableVideo];
    [_agoraKit startPreview];
    [_agoraKit setupLocalVideo:videoCanvas];
    
}
#pragma mark - AgoraDirectCdnStreamingEventDelegate
-(void)onDirectCdnStreamingStateChanged:(AgoraDirectCdnStreamingState)state
                                  error:(AgoraDirectCdnStreamingError)error
                                message:(NSString *)message{
    if (state == AgoraDirectCdnStreamingStateRunning && error == AgoraDirectCdnStreamingErrorOK) {
        
    }
}
#pragma mark - AgoraRtcEngineDelegate
//自己加入房间
-(void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinChannel:(NSString *)channel withUid:(NSUInteger)uid elapsed:(NSInteger)elapsed{
    [self.agoraKit muteAllRemoteVideoStreams:false];
    [self.agoraKit muteAllRemoteAudioStreams:false];
}
//主播加入房间
-(void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinedOfUid:(NSUInteger)uid elapsed:(NSInteger)elapsed{
    
}
- (void)rtcEngine:(AgoraRtcEngineKit *)engine tokenPrivilegeWillExpire:(NSString *)token
{
    __weak typeof(self) weakSelf = self;
    [self fetchAgoraRtcToken:^(NSString *rtcToken,NSUInteger agoraUserId) {
        [weakSelf.agoraKit renewToken:rtcToken];
    }];
}

- (void)rtcEngineRequestToken:(AgoraRtcEngineKit *)engine
{
    __weak typeof(self) weakSelf = self;
    [self fetchAgoraRtcToken:^(NSString *rtcToken,NSUInteger agoraUserId) {
        [weakSelf.agoraKit joinChannelByToken:rtcToken channelId:_room.channel info:nil uid:0 joinSuccess:^(NSString *channel, NSUInteger uid, NSInteger elapsed) {
        }];
    }];
}

- (void)fetchAgoraRtcToken:(void (^)(NSString *rtcToken ,NSUInteger agoraUserId))aCompletionBlock;
{
    _room.channel = _room.channel.length > 0 ? _room.channel : _room.roomId;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:nil
                                                     delegateQueue:[NSOperationQueue mainQueue]];
    NSString* strUrl = [NSString stringWithFormat:@"http://a1.easemob.com/token/rtcToken/v1?userAccount=%@&channelName=%@&appkey=%@",[EMClient sharedClient].currentUsername, _room.channel, [EMClient sharedClient].options.appkey];
    NSString*utf8Url = [strUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
    NSURL* url = [NSURL URLWithString:utf8Url];
    NSMutableURLRequest* urlReq = [[NSMutableURLRequest alloc] initWithURL:url];
    [urlReq setValue:[NSString stringWithFormat:@"Bearer %@",[EMClient sharedClient].accessUserToken ] forHTTPHeaderField:@"Authorization"];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:urlReq completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if(data) {
            NSDictionary* body = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
            NSLog(@"%@",body);
            if(body) {
                NSString* resCode = [body objectForKey:@"code"];
                if([resCode isEqualToString:@"RES_0K"]) {
                    NSString* rtcToken = [body objectForKey:@"accessToken"];
                    NSUInteger agoraUserId = [[body objectForKey:@"agoraUserId"] integerValue];
                    if (aCompletionBlock)
                        aCompletionBlock(rtcToken,agoraUserId);
                }
            }
        }
    }];

    [task resume];
}

#pragma mark - EMClientDelegate

- (void)connectionStateDidChange:(EMConnectionState)aConnectionState
{
    __weak typeof(self) weakSelf = self;
    //断网重连后，修改直播间状态为ongoing并重新推流&加入聊天室
    if (aConnectionState == EMConnectionConnected) {
        [[EaseHttpManager sharedInstance] modifyLiveroomStatusWithOngoing:_room completion:^(EaseLiveRoom *room, BOOL success) {
            if (success)
                _room = room;
            [weakSelf.chatview joinChatroomWithIsCount:NO
                                        completion:^(BOOL success) {
                                            if (success) {
                                                [weakSelf.headerListView loadHeaderListWithChatroomId:_room.chatroomId];
                                            }
                                        }];
            [weakSelf.agoraKit enableLocalVideo:YES];
            [weakSelf.agoraKit enableLocalAudio:YES];
        }];
    }
}

//切换前后摄像头
- (void)didSelectChangeCameraButton
{

    [self.agoraKit switchCamera];
}

- (UIWindow*)subWindow
{
    if (_subWindow == nil) {
        _subWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, KScreenHeight, KScreenWidth, 290.f)];
    }
    return _subWindow;
}

- (UIImageView*)backImageView
{
    if (_backImageView == nil) {
        _backImageView = [[UIImageView alloc]initWithFrame:CGRectMake(0, 0, KScreenWidth, KScreenHeight)];
        _backImageView.contentMode = UIViewContentModeScaleAspectFill;
        UIImage *image = [[SDImageCache sharedImageCache] imageFromMemoryCacheForKey:_room.coverPictureUrl];
        __weak typeof(self) weakSelf = self;
        if (!image) {
            [[SDWebImageDownloader sharedDownloader] downloadImageWithURL:[NSURL URLWithString:_room.coverPictureUrl]
                                                                     options:SDWebImageDownloaderUseNSURLCache
                                                                    progress:NULL
                                                                   completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                                                                       if (image) {
                                                                           [[SDImageCache sharedImageCache] storeImage:image forKey:_room.coverPictureUrl toDisk:NO completion:^{
                                                                               weakSelf.backImageView.image = image;
                                                                           }];
                                                                       } else {
                                                                           weakSelf.backImageView.image = [UIImage imageNamed:@"default_back_image"];
                                                                       }
                                                                   }];
           }
        _backImageView.image = image;
    }
    return _backImageView;
}

- (EaseLiveHeaderListView*)headerListView
{
    if (_headerListView == nil) {
        _headerListView = [[EaseLiveHeaderListView alloc] initWithFrame:CGRectMake(0, kDefaultTop, KScreenWidth, 40.f) room:_room];
        _headerListView.delegate = self;
        [_headerListView setLiveCastDelegate];
    }
    return _headerListView;
}

- (UILabel*)roomNameLabel
{
    if (_roomNameLabel == nil) {
        _roomNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 69.f, KScreenWidth - 20.f, 15)];
        _roomNameLabel.text = [NSString stringWithFormat:@"%@: %@" ,NSLocalizedString(@"live.room.name", @"Room ID") ,_room.roomId];
        _roomNameLabel.font = [UIFont systemFontOfSize:12.f];
        _roomNameLabel.textAlignment = NSTextAlignmentRight;
        _roomNameLabel.textColor = [UIColor whiteColor];
    }
    return _roomNameLabel;
}

- (EaseChatView*)chatview
{
    if (_chatview == nil) {
        _chatview = [[EaseChatView alloc] initWithFrame:CGRectMake(0, CGRectGetHeight(self.view.bounds) - 208, CGRectGetWidth(self.view.bounds), 200) room:_room isPublish:YES customMsgHelper:_customMsgHelper];
        _chatview.delegate = self;
    }
    return _chatview;
}

- (CTCallCenter *)callCenter {
    if (!_callCenter) {
        _callCenter = [[CTCallCenter alloc] init];
    }
    return _callCenter;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)didSelectedExitButton
{
    EaseFinishLiveView *finishView = [[EaseFinishLiveView alloc]initWithTitleInfo:@"确定结束直播?"];
    [self.view addSubview:finishView];
    [finishView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(16);
        make.right.equalTo(self.view).offset(-16);
        make.height.equalTo(@220);
        make.center.equalTo(self.view);
    }];
    __weak EaseFinishLiveView *weakFinishView = finishView;
    __weak EasePublishViewController *weakSelf = self;
    [finishView setDoneCompletion:^(BOOL isFinish) {
        if (isFinish) {
            _isFinishBroadcast = YES;
            [weakSelf didClickFinishButton];
        }
        [weakFinishView removeFromSuperview];
    }];
}

#pragma mark - Action

- (void)closeAction
{
    [self.subWindow resignKeyWindow];
    [UIView animateWithDuration:0.3 animations:^{
        self.subWindow.top = KScreenHeight;
    } completion:^(BOOL finished) {
        self.subWindow.hidden = YES;
        [self.view.window makeKeyAndVisible];
    }];
}

#pragma mark - EaseLiveHeaderListViewDelegate

- (void)didSelectHeaderWithUsername:(NSString *)username
{
    if ([self.subWindow isKeyWindow]) {
        [self closeAction];
        return;
    }
    EaseProfileLiveView *profileLiveView = [[EaseProfileLiveView alloc] initWithUsername:username
                                                                              chatroomId:_room.chatroomId
                                                                                 isOwner:YES];
    profileLiveView.delegate = self;
    [profileLiveView showFromParentView:self.view];
}

#pragma  mark - TapBackgroundViewDelegate

- (void)didTapBackgroundView:(EaseBaseSubView *)profileView
{
    [profileView removeFromParentView];
}

- (void)didClickFinishButton
{
    __weak EasePublishViewController *weakSelf = self;
    
    dispatch_block_t block = ^{
        [weakSelf.chatview leaveChatroomWithIsCount:NO
                                         completion:^(BOOL success) {
                                             if (success) {
                                                 [[EMClient sharedClient].chatManager deleteConversation:_room.chatroomId isDeleteMessages:YES completion:NULL];
                                             } else {
                                                 [weakSelf showHint:@"退出聊天室失败"];
                                             }
                                             
                                             [UIApplication sharedApplication].idleTimerDisabled = NO;
                                             [weakSelf dismissViewControllerAnimated:YES completion:^{
                                                 if (_finishBroadcastCompletion) {
                                                     _finishBroadcastCompletion(YES);
                                                 }
                                             }];
                                         }];
    };
    [[EaseHttpManager sharedInstance] modifyLiveroomStatusWithOffline:_room completion:^(EaseLiveRoom *room, BOOL success) {
        if (success) {
            _room = room;
//            if ([_room.liveroomType isEqualToString:kLiveBroadCastingTypeLIVE]) {
//                [weakSelf.session stopStreaming];//结束推流
//                [weakSelf.session destroy];
//            }
//            if ([_room.liveroomType isEqualToString:kLiveBroadCastingTypeAGORA_SPEED_LIVE]) {
//                [weakSelf.agoraKit leaveChannel:nil];
//                [AgoraRtcEngineKit destroy];
//            }
            [EaseHttpManager.sharedInstance deleteLiveRoomWithRoomId:_room.roomId completion:^(BOOL success) {
                if ([_room.liveroomType isEqualToString:kLiveBoardCastingTypeAGORA_CND_LIVE] || [_room.liveroomType isEqualToString:kLiveBroadCastingTypeAGORA_INTERACTION_LIVE]) {
                    [weakSelf.agoraKit stopDirectCdnStreaming];
                    [weakSelf.agoraKit stopPreview];
                    [AgoraRtcEngineKit destroy];
                }else{
                    [weakSelf.agoraKit leaveChannel:nil];
                    [AgoraRtcEngineKit destroy];
                }
                
                _isFinishBroadcast = YES;
                //重置本地保存的直播间id
                EaseDefaultDataHelper.shared.currentRoomId = @"";
                [EaseDefaultDataHelper.shared archive];
                block();
            }];
            
        }
        
    }];
}

- (void)didClickContinueButton
{
    [self _recoverLive];
}

#pragma mark - EaseChatViewDelegate

//礼物列表
- (void)didSelectGiftButton:(BOOL)isOwner
{
    if (isOwner) {
        EaseGiftListView *giftListView = [[EaseGiftListView alloc]init];
        giftListView.delegate = self;
        [giftListView showFromParentView:self.view];
    }
}

//有观众送礼物
- (void)userSendGifts:(EMMessage*)msg count:(NSInteger)count
{
    [_customMsgHelper userSendGifts:msg count:count backView:self.view];
    
    EMCustomMessageBody *msgBody = (EMCustomMessageBody*)msg.body;
    NSString *giftid = [msgBody.ext objectForKey:@"id"];
    
    _totalGifts += count;
    ++_giftsNum;
    [self.headerListView.liveCastView setNumberOfGift:_totalGifts];
    //礼物份数
    EaseDefaultDataHelper.shared.giftNumbers = [NSString stringWithFormat:@"%ld",(long)_giftsNum];
    //礼物合计总数
    EaseDefaultDataHelper.shared.totalGifts = [NSString stringWithFormat:@"%ld",(long)_totalGifts];
    //送礼物人列表
    if (![EaseDefaultDataHelper.shared.rewardCount containsObject:msg.from]) {
        [EaseDefaultDataHelper.shared.rewardCount addObject:msg.from];
    }
    NSMutableDictionary *giftDetailDic = (NSMutableDictionary*)[EaseDefaultDataHelper.shared.giftStatisticsCount objectForKey:giftid];
    if (!giftDetailDic) giftDetailDic = [[NSMutableDictionary alloc]init];
    long long num = [(NSString*)[giftDetailDic objectForKey:msg.from] longLongValue];
    [giftDetailDic setObject:[NSString stringWithFormat:@"%lld",(num+count)] forKey:msg.from];
    //礼物统计字典
    [EaseDefaultDataHelper.shared.giftStatisticsCount setObject:giftDetailDic forKey:giftid];
    [EaseDefaultDataHelper.shared archive];
}

//弹幕
- (void)didSelectedBarrageSwitch:(EMMessage*)msg
{
    [_customMsgHelper barrageAction:msg backView:self.view];
}

- (void)easeChatViewDidChangeFrameToHeight:(CGFloat)toHeight
{
    if ([self.subWindow isKeyWindow]) {
        return;
    }
    
    if (toHeight == 200) {
        [self.view removeGestureRecognizer:self.singleTapGR];
    } else {
        [self.view addGestureRecognizer:self.singleTapGR];
    }
    
    if (!self.chatview.hidden) {
        [UIView animateWithDuration:0.3 animations:^{
            CGRect rect = self.chatview.frame;
            rect.origin.y = self.view.frame.size.height - toHeight;
            self.chatview.frame = rect;
        }];
    }
}

//收到点赞
- (void)didReceivePraiseMessage:(EMMessage *)message
{
    [_customMsgHelper praiseAction:_chatview];
    EMCustomMessageBody *customBody = (EMCustomMessageBody*)message.body;
    _praiseNum += [(NSString*)[customBody.ext objectForKey:@"num"] integerValue];
    [self.headerListView.liveCastView setNumberOfPraise:_praiseNum];
    EaseDefaultDataHelper.shared.praiseStatisticstCount = [NSString stringWithFormat:@"%ld",(long)_praiseNum];
    [EaseDefaultDataHelper.shared archive];
}

//操作观众对象
- (void)didSelectUserWithMessage:(EMMessage *)message
{
    [self.view endEditing:YES];
    if (![message.from isEqualToString:_room.anchor]) {
        EaseAudienceBehaviorView *audienceBehaviorView = [[EaseAudienceBehaviorView alloc]initWithOperateUser:message.from chatroomId: _room.chatroomId];
        audienceBehaviorView.delegate = self;
        [audienceBehaviorView showFromParentView:self.view];
    }
}

//主播信息卡片
- (void)didClickAnchorCard:(EaseLiveRoom *)room
{
    [self.view endEditing:YES];
    EaseAnchorCardView *anchorCardView = [[EaseAnchorCardView alloc]initWithLiveRoom:room];
    anchorCardView.delegate = self;
    [anchorCardView showFromParentView:self.view];
}

//成员列表
- (void)didSelectMemberListButton:(BOOL)isOwner currentMemberList:(NSMutableArray*)currentMemberList
{
    [self.view endEditing:YES];
    EaseAdminView *adminView = [[EaseAdminView alloc] initWithChatroomId:_room
                                                                 isOwner:isOwner
                                                                currentMemberList:currentMemberList];
    adminView.delegate = self;
    [adminView showFromParentView:self.view];
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@"\n"]) {
        [textView resignFirstResponder];
        return NO;
    }
    return YES;
}

#pragma mark - EaseProfileLiveViewDelegate

#pragma mark - EMChatroomManagerDelegate

extern bool isAllTheSilence;
- (void)chatroomAllMemberMuteChanged:(EMChatroom *)aChatroom isAllMemberMuted:(BOOL)aMuted
{
    isAllTheSilence = aMuted;
    if ([aChatroom.chatroomId isEqualToString:_room.chatroomId]) {
        if (aMuted) {
            [self showHint:@"全员禁言开启！"];
        } else {
            [self showHint:@"解除全员禁言！"];
        }
    }
}

- (void)chatroomWhiteListDidUpdate:(EMChatroom *)aChatroom addedWhiteListMembers:(NSArray *)aMembers
{
    if ([aChatroom.chatroomId isEqualToString:_room.chatroomId]) {
        NSMutableString *text = [NSMutableString string];
        for (NSString *name in aMembers) {
            [text appendString:name];
        }
        [self showHint:[NSString stringWithFormat:@"被加入白名单:%@",text]];
    }
}

- (void)chatroomWhiteListDidUpdate:(EMChatroom *)aChatroom removedWhiteListMembers:(NSArray *)aMembers
{
    if ([aChatroom.chatroomId isEqualToString:_room.chatroomId]) {
        NSMutableString *text = [NSMutableString string];
        for (NSString *name in aMembers) {
            [text appendString:name];
        }
        [self showHint:[NSString stringWithFormat:@"从白名单移除:%@",text]];
    }
}

- (void)chatroomMuteListDidUpdate:(EMChatroom *)aChatroom
                addedMutedMembers:(NSArray *)aMutes
                       muteExpire:(NSInteger)aMuteExpire
{
    if ([aChatroom.chatroomId isEqualToString:_room.chatroomId]) {
        NSMutableString *text = [NSMutableString string];
        for (NSString *name in aMutes) {
            [text appendString:name];
        }
//        [self showHint:[NSString stringWithFormat:@"禁言成员:%@",text]];
        [self showHint:@"已被禁言"];
    }
}

- (void)chatroomMuteListDidUpdate:(EMChatroom *)aChatroom
              removedMutedMembers:(NSArray *)aMutes
{
    if ([aChatroom.chatroomId isEqualToString:_room.chatroomId]) {
        NSMutableString *text = [NSMutableString string];
        for (NSString *name in aMutes) {
            [text appendString:name];
        }
//        [self showHint:[NSString stringWithFormat:@"解除禁言:%@",text]];
        [self showHint:[NSString stringWithFormat:@"已解除禁言"]];
    }
}

- (void)chatroomOwnerDidUpdate:(EMChatroom *)aChatroom
                      newOwner:(NSString *)aNewOwner
                      oldOwner:(NSString *)aOldOwner
{
    __weak EasePublishViewController *weakSelf = self;
    if ([aChatroom.chatroomId isEqualToString:_room.chatroomId]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"" message:[NSString stringWithFormat:@"聊天室创建者有更新:%@",aChatroom.chatroomId] preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"publish.ok", @"Ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if ([aOldOwner isEqualToString:EMClient.sharedClient.currentUsername]) {
                if ([_room.liveroomType isEqualToString:kLiveBoardCastingTypeAGORA_CND_LIVE] || [_room.liveroomType isEqualToString:kLiveBroadCastingTypeAGORA_INTERACTION_LIVE]) {
                    [weakSelf.agoraKit stopDirectCdnStreaming];
                    [weakSelf.agoraKit stopPreview];
                }
                if ([_room.liveroomType isEqualToString:kLiveBroadCastingTypeAGORA_SPEED_LIVE]) {
                    [weakSelf.agoraKit leaveChannel:nil];
                    [AgoraRtcEngineKit destroy];
                }
                _isFinishBroadcast = YES;
                //重置本地保存的直播间id
                EaseDefaultDataHelper.shared.currentRoomId = @"";
                [EaseDefaultDataHelper.shared archive];
                [UIApplication sharedApplication].idleTimerDisabled = NO;
                [weakSelf dismissViewControllerAnimated:YES completion:^{
                    UIViewController *view = [[EaseLiveViewController alloc] initWithLiveRoom:_room];
                    view.modalPresentationStyle = 0;
                    [weakSelf.navigationController presentViewController:view animated:YES completion:NULL];
                    if (_finishBroadcastCompletion) {
                        _finishBroadcastCompletion(YES);
                    }
                }];
            }
        }];
        
        [alert addAction:ok];
        alert.modalPresentationStyle = 0;
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)didDismissFromChatroom:(EMChatroom *)aChatroom reason:(EMChatroomBeKickedReason)aReason
{
//    if (aReason == 0)
//        [MBProgressHUD showMessag:[NSString stringWithFormat:@"被移出直播聊天室 %@", aChatroom.subject] toView:nil];
//    if (aReason == 1)
//        [MBProgressHUD showMessag:[NSString stringWithFormat:@"直播聊天室 %@ 已解散", aChatroom.subject] toView:nil];
//    if (aReason == 2)
//        [MBProgressHUD showMessag:@"您的账号已离线" toView:nil];
//    [self didClickFinishButton];
}
-(void)userDidJoinChatroom:(EMChatroom *)aChatroom user:(NSString *)aUsername{
    [self.headerListView loadHeaderListWithChatroomId:_room.chatroomId];
}
-(void)userDidLeaveChatroom:(EMChatroom *)aChatroom user:(NSString *)aUsername{
    [self.headerListView loadHeaderListWithChatroomId:_room.chatroomId];
}
- (void)setBtnStateInSel:(NSInteger)num
{
    if (num == 1) {
        self.chatview.hidden = YES;
        self.headerListView.hidden = YES;
    } else {
        self.chatview.hidden = NO;
        self.headerListView.hidden = NO;
    }
}

- (void)_recoverLive
{
    while (!_isload) {
        _isload = YES;
    }
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat y = endFrame.origin.y;
    
    if ([self.subWindow isKeyWindow]) {
        if (y == KScreenHeight) {
            [UIView animateWithDuration:0.3 animations:^{
                self.subWindow.top = KScreenHeight - 290.f;
                self.subWindow.height = 290.f;
            }];
        } else  {
            [UIView animateWithDuration:0.3 animations:^{
                self.subWindow.top = 0;
                self.subWindow.height = KScreenHeight;
            }];
        }
    }
}

#pragma mark - override

- (void)setupForDismissKeyboard
{
    _singleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                           action:@selector(tapAnywhereToDismissKeyboard:)];
}

- (void)tapAnywhereToDismissKeyboard:(UIGestureRecognizer *)gestureRecognizer {
    [self.view endEditing:YES];
    [self.chatview endEditing:YES];
}

@end
