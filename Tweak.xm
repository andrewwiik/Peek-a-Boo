#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioServices.h>
#include <IOKit/hid/IOHIDEventSystem.h>
#include <IOKit/hid/IOHIDEventSystemClient.h>
#include <stdio.h>
#include <dlfcn.h>
#include <sys/sysctl.h>

static CGFloat SENSITIVITY = 1.0;
CGFloat FIRST_HALF = 0.35;

static NSDictionary *globalSettings;
static BOOL isEnabled = YES;
static BOOL hapticOnPeek = YES;
static BOOL hapticOnPop = YES;

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
    hapticInfo = @{ @"OnDuration" : @(0.0f), @"OffDuration" : @(duration), @"TotalDuration" : @(duration), @"Intensity" : @(intensity) };
    if (!hapticPlayerInitialized) {
        FigVibratorInitialize();
        hapticPlayerInitialized = YES;
    }
    FigVibratorPlayVibrationWithDictionary((__bridge CFDictionaryRef)hapticInfo, 0, 0, NULL, nil);
}

void hapticPeekVibe(){
    if (!hapticOnPeek) return;
    hapticFeedback(1.0, 1.0);
}

void hapticPopVibe(){
    if (!hapticOnPop) return;
    hapticFeedback(3.0, 2.0);
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
}

-(void)_setPressure:(CGFloat)arg1 resetPrevious:(BOOL)arg2 {
    self.shouldUsePreviousForce = arg2;
    %orig([self _pressure], arg2);
}

- (void)_clonePropertiesToTouch:(UITouch *)touch {
    %orig;
    touch.pab_force = self.pab_force;
}

- (CGFloat)_pressure {
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
                    CGFloat densityValue = (lastDensity * FIRST_HALF) + (touchDensity*(1.4 * SENSITIVITY) * (1.1 - FIRST_HALF));
                    CGFloat qualityValue = (lastQuality * FIRST_HALF) + (touchQuality*(3 * SENSITIVITY) * (1.1 - FIRST_HALF));
                    CGFloat radiusValue = (lastRadius * FIRST_HALF) + (touchRadius*(2.6 * SENSITIVITY) * (1.0 - FIRST_HALF));

                    pressure = (((((((CGFloat)100*qualityValue)+((CGFloat)100*densityValue))/1.4)*(radiusValue+1))/14)*SENSITIVITY);

                    lastQuality = qualityValue;
                    lastDensity = densityValue;
                    lastRadius = radiusValue;

                    lowestQuality = 0.7;
                    lowestDensity = 0.75;
                    lastTouchQuality = touchQuality;
                    lastTouchRadius = touchRadius;
                    lastTouchDensity = touchDensity;

                    CGFloat forceToReturn = (pressure*4.5)*(pressure * 0.01);

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
    return;
}
%end

%hook HapticClient 
- (id)initAndReturnError:(id*)error {
    return [NSClassFromString(@"HapticClient") new];
}

- (void)doInit {
    return;
}
-(BOOL)setupConnectionAndReturnError:(id*)arg1 {
    return YES;
}
-(BOOL)loadHapticPreset:(id)arg1 error:(id*)arg2 {
    return YES;
}
-(BOOL)prepareHapticSequence:(NSUInteger)arg1 error:(id*)arg2  {
    return YES;
}
-(BOOL)enableSequenceLooping:(NSUInteger)arg1 enable:(BOOL)arg2 error:(id*)arg3 {
    return YES;
}
-(BOOL)startHapticSequence:(NSUInteger)arg1 atTime:(CGFloat)arg2 withOffset:(CGFloat)arg3 {
    return YES;
}
-(BOOL)stopHapticSequence:(NSUInteger)arg1 atTime:(CGFloat)arg2 {
    return YES;
}
-(BOOL)detachHapticSequence:(NSUInteger)arg1 atTime:(CGFloat)arg2 {
    return YES;
}
-(void)startRunning:(id)arg1 {
    return;
}
-(BOOL)setChannelEventBehavior:(NSUInteger)arg1 channel:(NSUInteger)arg2 {
    return YES;
}
-(BOOL)startEventAndReturnToken:(NSUInteger)arg1 type:(NSUInteger)arg2 atTime:(CGFloat)arg3 channel:(NSUInteger)arg4 eventToken:(NSUInteger*)arg5 {
    return YES;
}
-(BOOL)stopEventWithToken:(NSUInteger)arg1 atTime:(CGFloat)arg2 channel:(NSUInteger)arg3 {
    return YES;
}
-(BOOL)clearEventsFromTime:(CGFloat)arg1 channel:(NSUInteger)arg2 {
    return YES;
}
-(BOOL)setParameter:(NSUInteger)arg1 atTime:(CGFloat)arg2 value:(float)arg3 channel:(NSUInteger)arg4 {
    return YES;
}
-(BOOL)loadHapticSequence:(id)arg1 reply:(id)arg2 {
    return YES;
}
-(BOOL)finish:(id)arg1 {
    return YES;
}
-(BOOL)setNumberOfChannels:(NSUInteger)arg1 error:(id*)arg2 {
    return YES;
}
%end

%hook _UIKeyboardTextSelectionGestureController
-(BOOL)forceTouchGestureRecognizerShouldBegin:(id)arg1 {
    return NO;
}
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

@interface UIDevice (priv)
- (BOOL)_supportsForceTouch;
@end

static NSString * machineModel() {
    static dispatch_once_t one;
    static NSString *model;
    dispatch_once(&one, ^{
        size_t size;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        void *machine = malloc(size);
        sysctlbyname("hw.machine", machine, &size, NULL, 0);
        model = [NSString stringWithUTF8String:(const char *)machine];
        free(machine);
    });
    return model;
}

%ctor {

    if ([[UIDevice currentDevice] _supportsForceTouch]) {
        return;
    }
    reloadPrefs();

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadPrefs,
        CFSTR("com.creatix.peek-a-boo.prefschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    %init;
    
    if (![machineModel() isEqualToString:@"iPhone11,8"]) {
        %init(Haptics);
    }
}