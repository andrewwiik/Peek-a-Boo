#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioServices.h>
#include <IOKit/hid/IOHIDEventSystem.h>
#include <IOKit/hid/IOHIDEventSystemClient.h>
#include <stdio.h>
#include <dlfcn.h>

static CGFloat SENSITIVITY = 1.0;
CGFloat FIRST_HALF = 0.35;


static NSDictionary *globalSettings;
static BOOL isEnabled = YES;
static BOOL hapticOnPeek = YES;
static BOOL hapticOnPop = YES;

#define isPad (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)


int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef, int);
typedef struct __IOHIDServiceClient * IOHIDServiceClientRef;
int IOHIDServiceClientSetProperty(IOHIDServiceClientRef, CFStringRef, CFNumberRef);
typedef void* (*clientCreatePointer)(const CFAllocatorRef);
extern "C" void BKSHIDServicesCancelTouchesOnMainDisplay();

extern "C" {
    void AudioServicesPlaySystemSoundWithVibration(SystemSoundID inSystemSoundID, id unknown, NSDictionary *options);
    void FigVibratorInitialize(void);
    void FigVibratorPlayVibrationWithDictionary(CFDictionaryRef dict, int a, int b, void *c, CFDictionaryRef d);
}

static CGFloat lastQuality = 0;
static CGFloat lastDensity = 0;
static CGFloat lastRadius = 0;
static CGFloat pressure = 0;
static CGFloat force = 0;
static CGFloat lowestQuality = 0;
static CGFloat lowestDensity = 0;
static CGFloat lastTouchQuality = 0;
static CGFloat lastTouchDensity = 0;
static CGFloat lastTouchRadius = 0;
static NSDictionary *hapticInfo;
static NSInteger hapticLength = 20;

static BOOL hapticPlayerInitialized = NO;



%hook _UIAlertControllerActionSheetRegularPresentationController
%new
- (void)setFeedbackBehavior:(id)behavior {
   // NSLog(@"SET BEHAVIOR");
    return;
}
%end


@interface UITouch (Private)
@property (assign,setter=_setHidEvent:,nonatomic) IOHIDEventRef _hidEvent;
@property (nonatomic, assign) BOOL allowForceOnTouch; 
@property (nonatomic, retain) NSNumber *pab_force;
@property (nonatomic, assign) BOOL shouldUsePreviousForce;
- (CGFloat)_unclampedForce; 
- (CGFloat)computePressure;
-(void)_setPressure:(CGFloat)arg1 resetPrevious:(BOOL)arg2;
- (CGFloat)_standardForceAmount;
- (BOOL)_supportsForce;
- (CGFloat)_pressure;
@end

static void resetForceVariables() {
    lastQuality = 0;
    lastDensity = 0;
    lastRadius = 0;
    force = 0;
    pressure = 0;
    lowestDensity = 0;
    lowestQuality = 0;
    lastTouchQuality = 0;
    lastTouchDensity = 0;
    lastTouchRadius = 0;
}


static void hapticFeedback(CGFloat intensity, CGFloat durationMultiplier) {
    CGFloat duration = (hapticLength / 1000.0f)*durationMultiplier;
//FBWorkspaceEvent *event = [FBWorkspaceEvent eventWithName:@"SB3DTouchMenuHapticNow" handler:^{
    hapticInfo = @{ @"OnDuration" : @(0.0f), @"OffDuration" : @(duration), @"TotalDuration" : @(duration), @"Intensity" : @(intensity) };
    if (!hapticPlayerInitialized) {
        FigVibratorInitialize();
        hapticPlayerInitialized = YES;
    }
    FigVibratorPlayVibrationWithDictionary((__bridge CFDictionaryRef)hapticInfo, 0, 0, NULL, nil);
//];
//[[FBWorkspaceEventQueue sharedInstance] executeOrAppendEvent:event];
}

// extern "C" void AudioServicesPlaySystemSoundWithVibration(SystemSoundID inSystemSoundID, id unknown, NSDictionary *options);
void hapticPeekVibe(){
    if (!hapticOnPeek) return;
    hapticFeedback(1.0, 1.0);
    // CGFloat duration = [[userDefaults objectForKey:@"HapticVibLength"] floatValue] / 1000.0f;
    //     g_hapticInfo = [@{ @"OnDuration" : @(0.0f), @"OffDuration" : @(duration), @"TotalDuration" : @(duration), @"Intensity" : @(2.0f) } retain];

    // NSMutableDictionary* VibrationDictionary = [NSMutableDictionary dictionary];
    // NSMutableArray* VibrationArray = [NSMutableArray array ];
    // [VibrationArray addObject:[NSNumber numberWithBool:YES]];
    // [VibrationArray addObject:[NSNumber numberWithInt:30]]; //vibrate for 50ms
    // [VibrationDictionary setObject:VibrationArray forKey:@"VibePattern"];
    // [VibrationDictionary setObject:[NSNumber numberWithInt:1] forKey:@"Intensity"];
    // AudioServicesPlaySystemSoundWithVibration(4095,nil,VibrationDictionary);
}

void hapticPopVibe(){
    if (!hapticOnPop) return;
    hapticFeedback(3.0, 2.0);
    // NSMutableDictionary* VibrationDictionary = [NSMutableDictionary dictionary];
    // NSMutableArray* VibrationArray = [NSMutableArray array ];
    // [VibrationArray addObject:[NSNumber numberWithBool:YES]];
    // [VibrationArray addObject:[NSNumber numberWithInt:30]]; //vibrate for 50ms
    // [VibrationDictionary setObject:VibrationArray forKey:@"VibePattern"];
    // [VibrationDictionary setObject:[NSNumber numberWithInt:2] forKey:@"Intensity"];
    // AudioServicesPlaySystemSoundWithVibration(4095,nil,VibrationDictionary);
}

%hook UITouch
%property (nonatomic, assign) BOOL allowForceOnTouch;
%property (nonatomic, retain) NSNumber *pab_force;
%property (nonatomic, assign) BOOL shouldUsePreviousForce;

- (id)init {
    UITouch *orig = %orig;
    orig.pab_force = [NSNumber numberWithFloat:-1.0f];
    return orig;
}

- (void)_setHidEvent:(IOHIDEventRef)event {
    %orig;
    if (!isEnabled) return;
    self.pab_force = [NSNumber numberWithFloat:-1.0];
    [self _setPressure:[self _pressure] resetPrevious:NO];
}

-(void)setPhase:(NSInteger)phase {
    %orig;
    if (!isEnabled) return;
    if ([self phase] == UITouchPhaseEnded || [self phase] == UITouchPhaseCancelled) {
        resetForceVariables();
    } else {
        if ([self phase] == UITouchPhaseBegan) {
            resetForceVariables();
            self.pab_force = [NSNumber numberWithFloat:-1.0];
        }
        [self _setPressure:[self _pressure] resetPrevious:NO];
    }
    // if ([self phase] == UITouchPhaseBegan) {
    //     resetForceVariables();
    //     // self.pab_force = [self computePressure];
    //     // [self _setPressure:self.pab_force resetPrevious:self.shouldUsePreviousForce];
    // } else if ([self phase] == UITouchPhaseEnded || [self phase] == UITouchPhaseCancelled) {
    //     resetForceVariables();
    // }
}

// - (BOOL)_supportsForce {
//     return YES;
// }

-(void)_setPressure:(CGFloat)arg1 resetPrevious:(BOOL)arg2 {
    self.shouldUsePreviousForce = arg2;
    %orig([self _pressure], arg2);
}

// - (CGFloat)_pressure {
//     return self.pab_force;
// }

- (void)_clonePropertiesToTouch:(UITouch *)touch {
    %orig;
    touch.pab_force = self.pab_force;
}

// - (BOOL)_needsForceUpdate {
//     return [self _supportsForce];
// }

- (CGFloat)_pressure {
    // self.pab_force = 0;
    // return 0;
    if (!isEnabled) return 0;
    if (![self _supportsForce]) {
        return (CGFloat)0;
    }
    if ((CGFloat)[self.pab_force doubleValue] < 0) {
        if (self._hidEvent != nil) {
            if (IOHIDEventGetType(self._hidEvent) == kIOHIDEventTypeDigitizer) {
                if (IOHIDEventIsAbsolute(self._hidEvent)) {
                    // return 0;
                    CGFloat touchDensity = [[NSNumber numberWithFloat:IOHIDEventGetFloatValue(self._hidEvent, (IOHIDEventField)kIOHIDEventFieldDigitizerDensity)] doubleValue];
                    CGFloat touchRadius = [[NSNumber numberWithFloat:IOHIDEventGetFloatValue(self._hidEvent, (IOHIDEventField)kIOHIDEventFieldDigitizerMajorRadius)] doubleValue];
                    CGFloat touchQuality = [[NSNumber numberWithFloat:IOHIDEventGetFloatValue(self._hidEvent, (IOHIDEventField)kIOHIDEventFieldDigitizerQuality)] doubleValue];

                    if (touchDensity == 0 || touchRadius == 0 || touchQuality == 0) {
                        return 0;
                    }
                    // if (touch.quality == lastTouchQuality && touch.density == lastTouchDensity) return self.pab_force;

                    // CGFloat densityValue = lastDensity + ((touchDensity - lastTouchDensity)*(1.3 * SENSITIVITY));
                    // CGFloat qualityValue = lastQuality + ((touchQuality - lastTouchQuality)*(1.5 * SENSITIVITY));
                    // CGFloat radiusValue = lastRadius + ((touchRadius - lastTouchRadius)*(3 * SENSITIVITY));
                    CGFloat densityValue = (lastDensity * FIRST_HALF) + (touchDensity*(1.4 * SENSITIVITY) * (1.1 - FIRST_HALF));
                    CGFloat qualityValue = (lastQuality * FIRST_HALF) + (touchQuality*(3 * SENSITIVITY) * (1.1 - FIRST_HALF));
                    CGFloat radiusValue = (lastRadius * FIRST_HALF) + (touchRadius*(2.6 * SENSITIVITY) * (1.0 - FIRST_HALF));

                    // CGFloat densityValue = (touchDensity*(2 * SENSITIVITY));
                    // CGFloat qualityValue = (touchQuality*(2.5 * SENSITIVITY));
                    // CGFloat radiusValue = (touchRadius*(1.5 * SENSITIVITY));
                    // return 0;

                    // HBLogInfo(@"DENSITY FINAL DATA: %@",[NSNumber numberWithFloat:densityValue]);
                    // HBLogInfo(@"QUALITY FINAL DATA: %@",[NSNumber numberWithFloat:qualityValue]);
                    // HBLogInfo(@"RADIUS FINAL  DATA: %@",[NSNumber numberWithFloat:radiusValue]);
                    // HBLogInfo(@"MINOR RADIUS VALUE: %@", [NSNumber numberWithFloat:touch.minorRadius]);
                    // HBLogInfo(@"MAJOR RADIUS VALUE: %@", [NSNumber numberWithFloat:touch.radius]);
                    // HBLogInfo(@"DENSITY      VALUE: %@", [NSNumber numberWithFloat:touch.density]);
                    // HBLogInfo(@"QUALITY               VALUE: %@", [NSNumber numberWithFloat:touch.quality]);
                    // HBLogInfo(@"DENSITY: %@  QUALITY: %@", [NSNumber numberWithFloat:touchDensity], [NSNumber numberWithFloat:touchQuality]);
                    // HBLogInfo(@"IRREGULARITY VALUE: %@", [NSNumber numberWithFloat:ireg]);
                    // HBLogInfo(@"TWIST        VALUE: %@", [NSNumber numberWithFloat:touch.twist]);
                   // HBLogInfo(@"TOUCH: %@", event);

                    pressure = (((((CGFloat)100*qualityValue)+((CGFloat)100*densityValue))/1.4)*(radiusValue+1))/14;
                    // pressure = (((((CGFloat)100*qualityValue)+((CGFloat)100*densityValue))/1.4))/14;
                    //pressure = ((CGFloat)10*(CGFloat)qualityValue)

                    lastQuality = qualityValue;
                    lastDensity = densityValue;
                    lastRadius = radiusValue;

                    lowestQuality = 0.7;
                    lowestDensity = 0.75;
                    lastTouchQuality = touchQuality;
                    lastTouchRadius = touchRadius;
                    lastTouchDensity = touchDensity;

                    // Start

                   //  CGFloat MODIFIER = (1.3 * SENSITIVITY);
                   //  CGFloat qualityPercent = ((touchQuality/lowestQuality)-1) * MODIFIER;
                   //  CGFloat densityPercent = ((densityValue/lowestDensity)-1) * MODIFIER;
                   //  CGFloat densityForceValue = (8 * densityPercent)/(12 * SENSITIVITY);
                   //  CGFloat qualityForceValue = (8 * qualityPercent);
                   // // densityForceValue = pow(densityForceValue, 3.0);
                   //  //qualityForceValue = qualityForceValue;
                   //  qualityForceValue = qualityForceValue*(1.3 * SENSITIVITY);

                   //  if (qualityForceValue < 0) qualityForceValue = 0;
                   //  if (densityForceValue < 0) densityForceValue = 0;
                   //  if (densityForceValue > 1) {
                   //      densityForceValue = pow(densityForceValue,3.0);
                   //  }
                   //  force = (densityForceValue + qualityForceValue)/2;

                   //  // End
                    //force = force*fabs(1.0-[UIScreen mainScreen].scale);
                    // force = densityForceValue;
                   // force = pow(densityForceValue,[UIScreen mainScreen].scale);
                    // NSLog(@"DENSITY FORCE  VALUE: %@", [NSNumber numberWithFloat:densityForceValue]);
                    // NSLog(@"DENSITY LOWEST VALUE: %@", [NSNumber numberWithFloat:lowestDensity]);
                    // NSLog(@"QUALITY FORCE  VALUE: %@", [NSNumber numberWithFloat:qualityForceValue]);
                    // NSLog(@"QUALITY LOWEST VALUE: %@", [NSNumber numberWithFloat:lowestQuality]);
                    CGFloat forceToReturn = (pressure*4.5)*(pressure * 0.01);
                   // HBLogInfo(@"FORCE        VALUE: %@", [NSNumber numberWithFloat:forceToReturn]);
                    // HBLogInfo(@"STANDARD FORCE AMOUNT: %@", [NSNumber numberWithFloat:[self _standardForceAmount]]);
                    // return 0;

                    if (forceToReturn > 0) self.pab_force = [NSNumber numberWithFloat:forceToReturn];
                    else self.pab_force = [NSNumber numberWithFloat:0];
                    return (CGFloat)[self.pab_force doubleValue];
                }
            }
        }
        self.pab_force = [NSNumber numberWithFloat:0];
        return 0;
    }
    return (CGFloat)[self.pab_force doubleValue];
}
%end

%hook UIScreen
- (NSInteger)_forceTouchCapability {
	return isEnabled ? 2 : %orig;
}
%end

%hook UITraitCollection
- (NSInteger)forceTouchCapability {
	return isEnabled ? 2 : %orig;
}
+ (id)traitCollectionWithForceTouchCapability:(NSInteger)arg1 {
	return %orig(isEnabled ? 2 : arg1);
}
%end

%hook UIDevice
- (BOOL)_supportsForceTouch {
		return isEnabled;
}
%end


%group Haptics
static NSInteger const UITapticEngineFeedbackPeek = 0;
static NSInteger const UITapticEngineFeedbackPop = 1;
static NSInteger const UITapticEngineFeedbackCancel = 2;

%hook _UITapticEngine
-(void)actuateFeedback:(NSInteger)feedback {
   // HBLogInfo(@"FEEDBACK ACTUATED: %@", [NSNumber numberWithInt:feedback]);
    if (feedback == UITapticEngineFeedbackPop) {
        hapticPopVibe();
    } else if (feedback == UITapticEngineFeedbackPeek) {
        hapticPeekVibe();
    } else if (feedback == UITapticEngineFeedbackCancel) {
        hapticPeekVibe();
    }
    %orig;
}
- (void)setFeedbackBehavior:(id)behavior {
    %orig;
}
%end

%hook NCTransitionManager
-(void)longLookTransitionDelegate:(id)arg1 didBeginTransitionWithAnimator:(id)arg2 {
    hapticPeekVibe();
    %orig;
}
%end

%hook _UIFeedbackAVHapticPlayer
-(void)_playFeedback:(id)arg1 atTime:(CGFloat)arg2  {
    //hapticPeekVibe();
   // HBLogInfo(@"FEEDBACK: %@\n TIME: %@", arg1, [NSNumber numberWithFloat:arg2]);
    return;
}
%end

// %hook _UIFeedbackHapticEngine
// +(BOOL)_supportsPlayingFeedback:(id)arg1 {
//  return YES;
// }
// %end
%hook HapticClient 
- (id)initAndReturnError:(id*)error {
    return [NSClassFromString(@"HapticClient") new];
}

- (void)doInit {
    return;
}
-(BOOL)setupConnectionAndReturnError:(id*)arg1 {
    // NSLog(@"CALLED SOMETHING HAPTICS");
    return YES;
}
-(BOOL)loadHapticPreset:(id)arg1 error:(id*)arg2 {
    return YES;
}
-(BOOL)prepareHapticSequence:(unsigned long long)arg1 error:(id*)arg2  {
    return YES;
}
-(BOOL)enableSequenceLooping:(unsigned long long)arg1 enable:(BOOL)arg2 error:(id*)arg3 {
    return YES;
}
-(BOOL)startHapticSequence:(unsigned long long)arg1 atTime:(double)arg2 withOffset:(double)arg3 {
    return YES;
}
-(BOOL)stopHapticSequence:(unsigned long long)arg1 atTime:(double)arg2 {
    return YES;
}
-(BOOL)detachHapticSequence:(unsigned long long)arg1 atTime:(double)arg2 {
    return YES;
}
-(void)startRunning:(/*^block*/id)arg1 {
    return;
}
-(BOOL)setChannelEventBehavior:(unsigned long long)arg1 channel:(unsigned long long)arg2 {
    return YES;
}
-(BOOL)startEventAndReturnToken:(unsigned long long)arg1 type:(unsigned long long)arg2 atTime:(double)arg3 channel:(unsigned long long)arg4 eventToken:(unsigned long long*)arg5 {
    return YES;
}
-(BOOL)stopEventWithToken:(unsigned long long)arg1 atTime:(double)arg2 channel:(unsigned long long)arg3 {
    return YES;
}
-(BOOL)clearEventsFromTime:(double)arg1 channel:(unsigned long long)arg2 {
    return YES;
}
-(BOOL)setParameter:(unsigned long long)arg1 atTime:(double)arg2 value:(float)arg3 channel:(unsigned long long)arg4 {
    return YES;
}
-(BOOL)loadHapticSequence:(id)arg1 reply:(/*^block*/id)arg2 {
    return YES;
}
-(BOOL)finish:(/*^block*/id)arg1 {
    return YES;
}
-(BOOL)setNumberOfChannels:(unsigned long long)arg1 error:(id*)arg2 {
    //hapticPeekVibe();
    return YES;
}
%end



%hook _UIKeyboardTextSelectionGestureController
-(BOOL)forceTouchGestureRecognizerShouldBegin:(id)arg1 {
    return NO;
}
%end

%hook _UIPreviewPresentationController
// -(void)_revealTransitionDidComplete:(BOOL)arg1 {
//  if (arg1) {
//      hapticPopVibe();
//  }
//  %orig;
// }
// -(void)_previewTransitionDidComplete:(BOOL)arg1 {
//  if(arg1) {
//      hapticPeekVibe();
//  }
//  %orig;
// }
// -(void)_dismissTransitionDidComplete:(BOOL)arg1 {
//  %orig;
// }
%end

%hook UIPreviewInteractionController
-(void)commitInteractivePreview {
    hapticPopVibe();
    %orig;
}
-(BOOL)startInteractivePreviewWithGestureRecognizer:(id)arg1 {
    BOOL orig = %orig;
    if (orig) {
        hapticPeekVibe();
    }
    return orig;
}
%end
%end

// MSHookFunction(((void*)MSFindSymbol(NULL, "_IS_D2x")),(void*)_IS_D2x, (void**)&old__IS_D2x);

// extern "C" BOOL MGGetBoolAnswer(CFStringRef);
// %hookf(BOOL, MGGetBoolAnswer, CFStringRef key)
// {
//     #define k(key_) CFEqual(key, CFSTR(key_))
//     if (k("eQd5mlz0BN0amTp/2ccMoA")
//         || k("n/aVhqpGjESEbIjvJbEHKg") 
//         || k("+fgL2ovGydvB5CWd1JI1qg"))
//         return isEnabled;
//     return %orig;
// }

static void reloadPrefs() {
    NSString *mainIdentifier = [NSBundle mainBundle].bundleIdentifier;

    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", @"com.ioscreatix.peek-a-boo"];
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    [settings addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:path]];

    globalSettings = settings;

    SENSITIVITY = (CGFloat)[[globalSettings objectForKey:@"forceSensitivity"]?:@1.0 doubleValue];
    hapticLength = (NSInteger)[[globalSettings objectForKey:@"hapticLength"]?:@20 integerValue];
    isEnabled = (BOOL)[[globalSettings objectForKey:@"Enabled"]?:@TRUE boolValue];
    hapticOnPeek = (BOOL)[[globalSettings objectForKey:@"hapticOnPeek"]?:@TRUE boolValue];
    hapticOnPop = (BOOL)[[globalSettings objectForKey:@"hapticOnPop"]?:@TRUE boolValue];

    NSDictionary *appSettings = [settings objectForKey:mainIdentifier];
    if (appSettings) {
        isEnabled = (BOOL)[[appSettings objectForKey:@"Enabled"]?:((NSNumber *)[NSNumber numberWithBool:isEnabled]) boolValue];
        if (isEnabled) {
            SENSITIVITY = (CGFloat)[[appSettings objectForKey:@"forceSensitivity"]?:@(SENSITIVITY) doubleValue];
            hapticOnPeek = (BOOL)[[appSettings objectForKey:@"hapticOnPeek"]?:((NSNumber *)[NSNumber numberWithBool:hapticOnPeek]) boolValue];
            hapticOnPop = (BOOL)[[appSettings objectForKey:@"hapticOnPop"]?:((NSNumber *)[NSNumber numberWithBool:hapticOnPop]) boolValue];
            hapticLength = (NSInteger)[[appSettings objectForKey:@"hapticLength"]?:@(hapticLength) integerValue];
        }
    }
}


%ctor {
    reloadPrefs();

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadPrefs,
        CFSTR("com.creatix.peek-a-boo.prefschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    %init;
    %init(Haptics);
    // loadHook();
    // MSHookFunction(((void*)MSFindSymbol(NULL, "_IS_D2x")),(void*)_IS_D2x, (void**)&old__IS_D2x);
}