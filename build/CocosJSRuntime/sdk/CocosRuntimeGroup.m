//
//  CocosRuntimeGroup.m
//  CocosJSRuntime
//
//  Created by Rye on 10/29/15.
//  Copyright © 2015 kinglong huang. All rights reserved.
//

#import "CocosRuntimeGroup.h"
#import "FileDownloader.h"
#import "FileUtil.h"
#import "ZipHelper.h"
#import "CocosRuntime.h"

static GameInfo *gameInfo = nil;
static GameConfig *gameConfig = nil;
static GameManifest *gameManifest = nil;
static NSMutableArray *resGroups = nil;
static NSMutableDictionary *resGroupDict = nil;

/**/
static NSInteger downloadGroupSize = 0;

/* 当前正在下载的组名 */
static NSString *currentDownloadName = nil;

/* 当前正在下载的组 */
static ResGroup *currentDownloadGroup = nil;

/* 之前的预加载组名 */
static NSString *prevPreloadGroupName = @"";

/* 等待的下载队列，元素是组名 */
static NSMutableArray *waitingDownloadGroups = nil;

/* 当前静默下载的组在所有组中的索引 */
static int currentDownloadIndex = 0;

/* 静默下载是否开启 */
static BOOL silentDownloadEnabled = FALSE;

/* 是否有正在下载的组 */
static BOOL isGroupDownloading = FALSE;

/* 是否处于静默下载状态 */
static BOOL isInSilentDownloadState = FALSE;

/* 当前的文件下载器*/
static FileDownloader *currentFileDownloader = nil;

/* 是否处于取消下载的状态 */
static BOOL isInCancelDownloadState = FALSE;

/**/
static id<LoadingDelegate> resDownloadDelegate = nil;

@implementation CocosRuntimeGroup
+ (void) initialize: (GameInfo*) info config: (GameConfig*) config manifest: (GameManifest*) manifest
{
    gameInfo = info;
    gameConfig = config;
    gameManifest = manifest;
    resGroups = [manifest allResGroups];
    resGroupDict = [CocosRuntimeGroup getAllResGroupDict:resGroups];
}

+ (void) preloadResGroups: (NSString*) groupsString delegate: (id<LoadingDelegate>) delegate
{
    if (![CocosRuntimeGroup needToDownloadGroup:groupsString]) {
        //todo回调通知下载结束
        return;
    }
    
    isInSilentDownloadState = FALSE;
    
    if (currentDownloadGroup == nil || [waitingDownloadGroups containsObject:currentDownloadGroup.groupName]) {
        isInCancelDownloadState = TRUE;
        isGroupDownloading = FALSE;
        [CocosRuntimeGroup cancelCurrentDownload];
        // todo 取消之后的监听，解压之类的
        // Since we will cancel current download, the current download needs to be started again.
        // Therefore, decrease the index to make getNextResGroupForDownload happy.
        [CocosRuntimeGroup decreaseIndexOfSilentDownload];
        isInCancelDownloadState = FALSE;
        [CocosRuntimeGroup startDownloadGroups];
    }
    
    NSLog(@"===> preload resource groups: %@", groupsString);
    [CocosRuntimeGroup startDownloadGroups];
    resDownloadDelegate = delegate;
}

+ (void) reset
{
    waitingDownloadGroups = [NSMutableArray arrayWithCapacity:20];
    currentDownloadIndex = 0;
}

+ (void) clearDownloadState
{
    currentDownloadGroup = nil;
    isGroupDownloading = FALSE;
}

+ (void) updateGroup: (NSString*)groupName delegate: (id<LoadingDelegate>) delegate
{
    ResGroup *resGroup = [CocosRuntimeGroup findGroupByName:groupName];
    if (resGroup == nil) {
        NSLog(@"Can't find (%@) section in 'res_groups' of 'manifest.json'", groupName);
        return;
    }
    
    if ([resGroup isUpdated:gameInfo]) {
        NSLog(@"(%@) was updated, don't need to update it again!", groupName);
        // todo 通知成功
        
    } else {
        [CocosRuntimeGroup downloadResGroup:gameInfo group:resGroup delegate:delegate];
    }
}

+ (void) prepareWaitingDownloadGroups: (NSString*) groupsString
{
    NSArray *groupsNameArray = [groupsString componentsSeparatedByString:@":"];
    NSLog(@"===> prepareWaitingDownloadGroups:%@", groupsNameArray);
    
    currentDownloadName = [groupsNameArray objectAtIndex:0];
    long totalSize = 0;
    for (NSString *groupName in groupsNameArray) {
        if ([self isGroupUpdated:groupName]) {
            continue;
        }
        
        if ([waitingDownloadGroups containsObject:groupName]) {
            continue;
        }
        
        [waitingDownloadGroups addObject:groupName];
        
        ResGroup *resGroup = [CocosRuntimeGroup findGroupByName:groupName];
        if (resGroup != nil) {
            totalSize += resGroup.groupSize;
        }
    }
    
    // if downloading group is in the waiting download list, complete the download process first
    if (currentDownloadGroup != nil && [waitingDownloadGroups containsObject:currentDownloadGroup.groupName]) {
        [CocosRuntimeGroup removeGroupFromWaitingDownload: currentDownloadGroup.groupName];
        [waitingDownloadGroups insertObject:currentDownloadGroup.groupName atIndex:0];
    }
    
    // 将此次等待下载的进度进行保存
    if (waitingDownloadGroups.count != 0) {
        NSMutableArray *loadingInfos = [NSMutableArray arrayWithCapacity:10];
        for (NSString *groupName in waitingDownloadGroups) {
            ResGroup *resGroup = [CocosRuntimeGroup findGroupByName:groupName];
            if (resGroup != nil) {
                float percent = (float)(resGroup.groupSize / totalSize) * 100;
                
                LoadingInfo* downloadInfo = [[LoadingInfo alloc]initWith:[@"download" stringByAppendingString: groupName] percent:(NSInteger)(percent * 0.8) type:PROGRESS tip:resGroup.groupName];
                LoadingInfo* unzipInfo = [[LoadingInfo alloc]initWith:[@"unzip" stringByAppendingString: groupName] percent:(NSInteger)(percent * 0.2) type:PROGRESS tip:resGroup.groupName];
                [loadingInfos addObject: downloadInfo];
                [loadingInfos addObject: unzipInfo];
            }
        }
        [[CocosRuntime getLoadingProgressController] setLoadingInfoList:loadingInfos];
    }
    
}

+ (BOOL) needToDownloadGroup: (NSString*)groupString
{
    [CocosRuntimeGroup prepareWaitingDownloadGroups:groupString];
    if (waitingDownloadGroups.count == 0) {
        NSLog(@"%@ were downloaded, no need to download again!", groupString);
        return FALSE;
    }
    return TRUE;
}

+ (NSMutableDictionary*) getAllResGroupDict: (NSMutableArray*) resGroupArray
{
    resGroupDict = [NSMutableDictionary dictionaryWithCapacity:20];
    for (ResGroup *resGroup in resGroupArray) {
        [resGroupDict setObject:resGroup forKey:resGroup.groupName];
    }
    return resGroupDict;
}

+ (BOOL) isGroupUpdated: (NSString*) name
{
    ResGroup *group = [CocosRuntimeGroup findGroupByName:name];
    return group == nil ? FALSE : [group isUpdated:gameInfo];
}

+ (ResGroup*) findGroupByName: (NSString*) name
{
    return [resGroupDict objectForKey:name];
}

+ (BOOL) isGroupMD5Correct: (NSString*) md5 path: (NSString*) path
{
    NSString* fileMD5 = [FileUtil getFileMD5:path];
    if ([fileMD5 isEqualToString:fileMD5]) {
        return true;
    }
    return false;
}

+ (BOOL) unzipGroupFrom: (NSString*) fromPath to: (NSString*) toPath overwrite: (BOOL) overwrite
{
    return [ZipHelper unzipFileAtPath:fromPath toDestination:toPath];
}

+ (void) updateResGroup: (GameInfo*) gameInfo group: (ResGroup*) resGroup
{
    
    [CocosRuntimeGroup checkResGroup:gameInfo group:resGroup];
}

+ (void) checkResGroup: (GameInfo*) gameInfo group: (ResGroup*) resGroup
{
    NSString* localGroupPath = [FileUtil getLocalGroupPath:gameInfo group:resGroup];
    if ([CocosRuntimeGroup isGroupMD5Correct:resGroup.groupMD5 path:localGroupPath]) {
        [CocosRuntimeGroup unzipGroupFrom:localGroupPath to: [FileUtil getGameRootPath:gameInfo] overwrite: true];
    } else {
        [CocosRuntimeGroup downloadResGroup:gameInfo group:resGroup];
    }
}

+ (bool) isDownloadIndexValid: (NSInteger)index
{
    if (index >= 0 && index < resGroups.count) {
        return true;
    }
    return false;
}

+ (ResGroup*) getResGroupByIndex: (NSInteger)index
{
    return [resGroups objectAtIndex:index];
}

+ (void) removeGroupFromWaitingDownload: (NSString*)groupName
{
    if (waitingDownloadGroups.count == 0) {
        return;
    }
    
    for (NSInteger i = waitingDownloadGroups.count - 1; i >= 0; i--) {
        if ([[waitingDownloadGroups objectAtIndex:i] isEqualToString:groupName]) {
            [waitingDownloadGroups removeObjectAtIndex: i];
        }
    }
}

+ (NSString*) getCurrentGroupNameFromWaitingGroups
{
    if (waitingDownloadGroups == nil || waitingDownloadGroups.count == 0) {
        return nil;
    } else {
        return waitingDownloadGroups.firstObject;
    }
}

+ (BOOL) isInCancelDownloadState
{
    return isInCancelDownloadState;
}

+ (NSString*) getFirstGroupFromWaitingDownload
{
    if (waitingDownloadGroups != nil) {
        return [waitingDownloadGroups objectAtIndex:0];
    }
    return nil;
}

+ (void) removeFirstGroupFromWaitingDownload
{
    if (waitingDownloadGroups != nil && waitingDownloadGroups.count != 0) {
        [waitingDownloadGroups removeObjectAtIndex:0];
    }
}

+ (void) downloadResGroup: (GameInfo*) gameInfo group: (ResGroup*) resGroup delegate: (id<OnGroupUpdateDelegate>) delegate
{
    if (resGroup == nil) {
        NSLog(@"resGroup is null in startDownload!");
        return;
    }
    
    NSString *groupName = resGroup.groupName;
    if (isGroupDownloading) {
        NSLog(@"Oops, previous group: %@ , current group: %@", prevPreloadGroupName, groupName);
        return;
    }
    
    currentDownloadGroup = resGroup;
    isGroupDownloading = TRUE;
    prevPreloadGroupName = groupName;
    
    // todo将前台下载和后台下载的进度分开
    
    
    NSURL *requestUrl = [[NSURL alloc]initWithString:[[[gameInfo downloadUrl] stringByAppendingPathComponent:@"/"] stringByAppendingPathComponent:resGroup.groupURL]];
    
    ResourceGroupDownloadImpl* resDownloadImpl =  [[ResourceGroupDownloadImpl alloc] initWith:resGroup];
    currentFileDownloader = [[FileDownloader alloc] initWithURL:requestUrl delegate:resDownloadImpl];
    [currentFileDownloader startDownload];
}

+ (void) startDownloadGroups
{
    if (waitingDownloadGroups.count == 0) {
        NSLog(@"waiting download groups is empty now, download done!");
        // todo 通知下载结束
        return;
    }
    currentDownloadName = [CocosRuntimeGroup getFirstGroupFromWaitingDownload];
    
    OnGroupUpdateDelegateImpl* groupUpdateDelegate = [[OnGroupUpdateDelegateImpl alloc]init];
    [CocosRuntimeGroup updateGroup:currentDownloadName delegate:groupUpdateDelegate];
}

+ (void) cancelCurrentDownload
{
    // todo 添加取消通知
    currentDownloadName = nil;
    if (currentFileDownloader != nil) {
        [[currentFileDownloader downloadTask] cancel];
        currentFileDownloader = nil;
    }
}

/************************************ SilentDownload ********************************/

+ (BOOL) isSilentDownloadEnabled
{
    return silentDownloadEnabled;
}

+ (void) setSilentDownloadEnabled: (BOOL)isEnabled
{
    silentDownloadEnabled = isEnabled;
}

+ (int) increaseIndexOfSilentDownload
{
    ++currentDownloadIndex;
    NSLog(@"increase current download index: %d", currentDownloadIndex);
    return currentDownloadIndex;
}

+ (int) decreaseIndexOfSilentDownload
{
    --currentDownloadIndex;
    NSLog(@"decrease current download index: %d", currentDownloadIndex);
    return currentDownloadIndex;
}

+ (ResGroup*) getNextResGroupForDownload
{
    ResGroup* resGroup = nil;
    int nextDownloadIndex = [CocosRuntimeGroup increaseIndexOfSilentDownload];
    if ([CocosRuntimeGroup isDownloadIndexValid:nextDownloadIndex]) {
        resGroup = [CocosRuntimeGroup getResGroupByIndex:nextDownloadIndex];
    } else {
        NSLog(@"All group resources are downloaded, no need to download! Index = %d", nextDownloadIndex);
    }
    return resGroup;
}

+ (void) setInSilentDownloadState: (BOOL)inSilentDownload
{
    isInSilentDownloadState = inSilentDownload;
    if (isInSilentDownloadState) {
        // todo 设置解压线程等级为低
    } else {
        // todo 设置解压线程等级为正常
    }
}

+ (BOOL) isInSilentDownloadState
{
    return isInSilentDownloadState;
}

+ (void) silentDownloadNextGroup
{
    if (!silentDownloadEnabled) {
        return;
    }
    
    if (isGroupDownloading) {
        NSLog(@"group (%@) is downloading, don't start silent download! ", prevPreloadGroupName);
        return;
    }
    
    ResGroup *resGroup = [CocosRuntimeGroup getNextResGroupForDownload];
    if (resGroup == nil) {
        return;
    }
    
    NSLog(@"onSilentDownloadNextGroup (%@)", resGroup.groupName);
    [CocosRuntimeGroup prepareWaitingDownloadGroups:resGroup.groupName];
    if (waitingDownloadGroups.count == 0) {
        // todo 判断游戏是否已经关闭
        [CocosRuntimeGroup silentDownloadNextGroup];
    } else {
        [CocosRuntimeGroup setInSilentDownloadState:TRUE];
        [CocosRuntimeGroup startDownloadGroups];
    }
}
@end

@implementation ResourceGroupDownloadImpl

- (ResourceGroupDownloadImpl*) initWith:(ResGroup *)group
{
    if (self = [super init]) {
        resGroup = group;
    }
    return self;
}

- (void) onDownloadProgress:(double)progress
{
    NSInteger progressOffset = resGroup.groupSize * 0.8 * progress;
    [CocosRuntime notifyProgress: progressOffset unzipDone: false isFailed: false];
}

- (NSString*) onTempDownloaded:(NSString *)locationPath
{
    return locationPath;
}

- (void) onDownloadSuccess:(NSString *)path
{
    NSLog(@"===> BootGroupDownloadDelegateImpl Success");
    
    NSString *targetPath = [FileUtil getLocalGroupPath:gameInfo group: resGroup];
    @try {
        [FileUtil ensureDirectory:[FileUtil getParentDirectory:targetPath]];
        [FileUtil moveFileFrom:path to:targetPath overwrite:true];
        
        NSLog(@"===> download %@", resGroup.groupURL);
        
        if (![CocosRuntimeGroup unzipGroupFrom: targetPath to: [FileUtil getGameRootPath:gameInfo] overwrite: true]) {
            NSLog(@"===> unzip success");
        }
        
        [CocosRuntime notifyProgress: resGroup.groupSize unzipDone: false isFailed: false];
        [CocosRuntimeGroup removeFirstGroupFromWaitingDownload];
        // 发送通知告知下载解压成功
    }
    @catch (NSException *exception) {
        NSLog(@"move file error");
        [CocosRuntime notifyProgress: resGroup.groupSize unzipDone: true isFailed: true];
    }
}

- (void) onDownloadFailed
{
    NSLog(@"===> BootGroupDownloadDelegateImpl onDownloadFailed");
    [CocosRuntime notifyProgress: resGroup.groupSize unzipDone: true isFailed: true];
}
@end

/****************************** 分组更新监听 ***************************/

@implementation OnGroupUpdateDelegateImpl

- (OnGroupUpdateDelegateImpl*) initWith:(ResGroup *)group
{
    if (self = [super init]) {
        resGroup = group;
    }
    return self;
}

- (void) onProgressOfDownload: (long) written total:(long) total
{
    if (isInSilentDownloadState) {
        // 做进度通知
    }
}

- (void) onSuccessOfDownload: (long) total
{
    // todo 通知下载成功进度
}

- (void) onFailureOfDownload: (NSString*) errorMsg
{
    [CocosRuntimeGroup clearDownloadState];
    if ([CocosRuntimeGroup isSilentDownloadEnabled] && [CocosRuntimeGroup isInSilentDownloadState]) {
        [CocosRuntimeGroup decreaseIndexOfSilentDownload];
        [CocosRuntimeGroup silentDownloadNextGroup];
    } else {
        // todo 通知下载失败
    }
}

- (void) onSuccessOfUnzip: (long)total
{
    [CocosRuntimeGroup removeGroupFromWaitingDownload:resGroup.groupName];
    if (currentDownloadGroup != nil && ![currentDownloadGroup.groupName isEqualToString:resGroup.groupName]) {
        NSLog(@"Oops, some errors happened, current download group name: %@ downloaded group name: %@",currentDownloadGroup.groupName, resGroup.groupName);
        return;
    }
    
    if (currentDownloadGroup != nil) {
        [currentDownloadGroup setIsUpdated:TRUE];
    }
    
    [CocosRuntimeGroup clearDownloadState];
    
    // If there are another group needs to be downloaded, don't make silent download works.
    [CocosRuntimeGroup startDownloadGroups];
    
    if (waitingDownloadGroups.count == 0 && [CocosRuntimeGroup isSilentDownloadEnabled] && ![CocosRuntimeGroup isInCancelDownloadState]) {
        [CocosRuntimeGroup silentDownloadNextGroup];
    } else {
        NSLog(@"===> Don't silent download ..., isInCancelDownload: %d", [CocosRuntimeGroup isInCancelDownloadState]);
    }
}

- (void) onFailureOfUnzip: (NSString*) errorMsg
{
    // todo 填写错误类型
    [CocosRuntimeGroup clearDownloadState];
    if ([CocosRuntimeGroup isInSilentDownloadState]) {
        [CocosRuntimeGroup decreaseIndexOfSilentDownload];
        [CocosRuntimeGroup silentDownloadNextGroup];
    } else {
        // todo 通知返回下载失败
        NSLog(@"===> onFailureOfUnzip");
    }
}

- (void) onProgressOfUnzip: (float) percent
{
    // 如果是不是静默下载，则发送更新界面的通知
    if (![CocosRuntimeGroup isInSilentDownloadState]) {
        // todo 发送通知更新进度
        NSLog(@"===> onProgressOfUnzip: %f", percent);
    }
}
@end




