// Runs inside backboardd on iOS 16 (Daemon.x covers iOS 17+).
//
// iOS 16 has no Screen Distance (no EyeRelief), so this does the daemon's job
// itself, following what eyereliefd does on iOS 17:
// - every 80 s it takes one face sample through BiometricKit
//   (BKFaceDetectOperation on the AttentionAwareness sampler's BKDevicePearl).
//   The sample says whether a face was seen and how far away it is (mm).
// - a sample is too close (category 0) if a face was seen closer than the
//   threshold, far enough (1) if it was seen at or beyond it, and "no face" (2)
//   otherwise. Too close adds 1 to the count (4 / N with Custom Sensitivity),
//   far enough takes 1 off, no face takes 0.25 off; the count stays within
//   0...4 and at 4 the reminder is due.
// - the reminder is the same notify conversation with SpringBoard as on iOS 17
//   (PillShow, then samples every 0.3 s until the face is far enough or gone,
//   then PillHide / PillCancel).
// The test buttons in Settings (Trigger / TriggerDelayed) work here too.
//
// QD16_DRY_RUN: the automatic reminders only log what they would do and never
// show the pill. The test buttons still do.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "ScreenDistancePillPrefs.h"
#import "ScreenDistancePillLog.h"

#ifndef QD16_DRY_RUN
#define QD16_DRY_RUN 0
#endif

#define QD16_SAMPLE_INTERVAL 80
#define QD16_STOCK_THRESHOLD_MM 300
#define QD16_STOCK_SENSITIVITY 4.0f
#define QD16_NO_FACE_REDUCTION 0.25f
#define QD16_SAMPLE_TIMEOUT 5.0
#define QD16_PILL_SAMPLE_INTERVAL 0.3
#define QD16_PILL_MAX_DURATION 180
// first sample this long after backboardd starts
#define QD16_FIRST_SAMPLE_DELAY 20

@interface BKFaceDetectStateInfo : NSObject
@property (nonatomic, retain) NSNumber *distance;
@property (nonatomic, readonly) bool faceDetected;
@end

@interface BKFaceDetectOperation : NSObject
@property (nonatomic, assign) id delegate;
@property (nonatomic) double timeout;
- (instancetype)initWithDevice:(id)device;
- (void)startBioOperation:(bool)arg1 reply:(void (^)(intptr_t, intptr_t))reply;
@end

@interface AWPearlAttentionSampler : NSObject
@end

typedef NS_ENUM(NSInteger, QD16Category) {
	QD16CategoryTooClose = 0,
	QD16CategoryFarEnough = 1,
	QD16CategoryNoFace = 2,
};

static __weak AWPearlAttentionSampler *pearlSampler;

// settings SpringBoard publishes as notify states (see Daemon.x)
static uint64_t readStateInRange(const char *name, int *token, uint64_t min, uint64_t max) {
	uint64_t state = QDReadState(name, token);
	return state >= min && state <= max ? state : 0;
}

static BOOL tweakEnabled(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	return QDReadState(QD_ENABLED_STATE, &token) != QDEnabledStateOff;
}

// the threshold in mm, iOS's own 300 with Custom Sensitivity off
static NSInteger thresholdMillimeters(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	NSInteger custom = tweakEnabled() ? readStateInRange(QD_THRESHOLD_STATE, &token, 200, 500) : 0;
	return custom ?: QD16_STOCK_THRESHOLD_MM;
}

// too-close samples before a reminder
static float sensitivitySamples(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	float custom = tweakEnabled() ? readStateInRange(QD_SENSITIVITY_STATE, &token, 1, 20) : 0;
	return custom ?: QD16_STOCK_SENSITIVITY;
}

// SpringBoard's own notify states
static BOOL screenOffOrLocked(void) {
	static int blankedToken = NOTIFY_TOKEN_INVALID;
	static int lockToken = NOTIFY_TOKEN_INVALID;
	return QDReadState("com.apple.springboard.hasBlankedScreen", &blankedToken) != 0
		|| QDReadState("com.apple.springboard.lockstate", &lockToken) != 0;
}

#pragma mark - One face sample

// distance in mm, valid only if face
typedef void (^QD16SampleCompletion)(BOOL ok, BOOL face, double distance);

@interface QD16SampleOperation : NSObject
@property (nonatomic, strong) BKFaceDetectOperation *operation;
@property (nonatomic, copy) QD16SampleCompletion completion;
@property (nonatomic, strong) BKFaceDetectStateInfo *info;
@property (nonatomic) BOOL replyOK;
@end

static QD16SampleOperation *currentSample;

@implementation QD16SampleOperation

- (void)operation:(id)operation faceDetectStateChanged:(BKFaceDetectStateInfo *)info {
	// the last state before the operation finishes counts
	self.info = info;
}

- (void)operation:(id)operation finishedWithReason:(long long)reason {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self finishWithReason:reason];
	});
}

- (void)finishWithReason:(long long)reason {
	if (currentSample != self)
		return;
	currentSample = nil;
	QD16SampleCompletion completion = self.completion;
	self.completion = nil;
	if (!completion)
		return;
	BKFaceDetectStateInfo *info = self.info;
	QDDebugLog(@"sample finished, reason %lld, face %d, distance %@", reason, info.faceDetected, info.distance);
	if (!info)
		completion(NO, NO, 0);
	else
		completion(YES, info.faceDetected, info.distance.doubleValue);
}

@end

static void takeSample(QD16SampleCompletion completion) {
	if (currentSample) {
		completion(NO, NO, 0);
		return;
	}
	AWPearlAttentionSampler *sampler = pearlSampler;
	id pearl = sampler ? MSHookIvar<id>(sampler, "_pearlDevice") : nil;
	Class operationClass = objc_getClass("BKFaceDetectOperation");
	if (!pearl || !operationClass) {
		QDDebugLog(@"no sampler / Face ID device yet, skipping the sample");
		completion(NO, NO, 0);
		return;
	}
	QD16SampleOperation *sample = [QD16SampleOperation new];
	sample.completion = completion;
	sample.operation = [[operationClass alloc] initWithDevice:pearl];
	sample.operation.delegate = sample;
	sample.operation.timeout = QD16_SAMPLE_TIMEOUT;
	currentSample = sample;
	[sample.operation startBioOperation:YES reply:^(intptr_t success, intptr_t error) {
		if (success)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			QDDebugLog(@"sample could not start (%p)", (void *)error);
			[sample finishWithReason:-1];
		});
	}];
	// the operation has its own timeout, this is only a safety net
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((QD16_SAMPLE_TIMEOUT + 3) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[sample finishWithReason:-2];
	});
}

static QD16Category categoryForSample(BOOL face, double distance) {
	if (!face)
		return QD16CategoryNoFace;
	return distance >= thresholdMillimeters() ? QD16CategoryFarEnough : QD16CategoryTooClose;
}

#pragma mark - The pill

// all pill and counting state lives on the main queue
static BOOL pillActive;
static NSUInteger pillGeneration;
static float tooCloseCount;
static QDPillRequest nextPillRequest;

static void finishPill(BOOL distanceFine, NSString *reason) {
	if (!pillActive)
		return;
	pillActive = NO;
	pillGeneration++;
	notify_post(distanceFine ? QD_PILL_HIDE : QD_PILL_CANCEL);
	QDDebugLog(@"pill down: %@", reason);
}

static void samplePillDistance(NSUInteger generation) {
	if (!pillActive || generation != pillGeneration)
		return;
	takeSample(^(BOOL ok, BOOL face, double distance) {
		if (!pillActive || generation != pillGeneration)
			return;
		if (!ok) {
			finishPill(NO, @"distance sample failed");
			return;
		}
		QD16Category category = categoryForSample(face, distance);
		QDDebugLog(@"pill sample: face %d, %.0f mm, category %ld", face, distance, (long)category);
		if (category != QD16CategoryTooClose) {
			finishPill(YES, category == QD16CategoryNoFace ? @"no face" : @"safe distance");
			return;
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QD16_PILL_SAMPLE_INTERVAL * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			samplePillDistance(generation);
		});
	});
}

static void startPill(void) {
	QDPillRequest request = nextPillRequest;
	nextPillRequest = 0;
	if (pillActive) {
		QDDebugLog(@"pill already up, ignoring the new request");
		return;
	}
	pillActive = YES;
	NSUInteger generation = ++pillGeneration;
	QDDebugLog(@"asking SpringBoard for the pill (flags %llu, threshold %ld mm)", (unsigned long long)request, (long)thresholdMillimeters());

	static int showToken = NOTIFY_TOKEN_INVALID;
	if (showToken == NOTIFY_TOKEN_INVALID)
		notify_register_check(QD_PILL_SHOW, &showToken);
	notify_set_state(showToken, request);
	notify_post(QD_PILL_SHOW);

	samplePillDistance(generation);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, QD16_PILL_MAX_DURATION * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (generation == pillGeneration)
			finishPill(NO, @"timed out");
	});
}

#pragma mark - The 80 s rhythm

static void scheduleNextSample(NSTimeInterval delay);
static void takeCountedSample(void);

static void applySample(BOOL face, double distance) {
	QD16Category category = categoryForSample(face, distance);
	float old = tooCloseCount;
	switch (category) {
		case QD16CategoryTooClose:
			tooCloseCount = MIN(old + QD16_STOCK_SENSITIVITY / sensitivitySamples(), QD16_STOCK_SENSITIVITY);
			break;
		case QD16CategoryFarEnough:
			tooCloseCount = MAX(old - 1, 0);
			break;
		case QD16CategoryNoFace:
			tooCloseCount = MAX(old - QD16_NO_FACE_REDUCTION, 0);
			break;
	}
	QDDebugLog(@"sample: face %d, %.0f mm, category %ld, too-close count %.2f -> %.2f", face, distance, (long)category, old, tooCloseCount);
}

// Whether the front app is one Apple never samples in (Camera, FaceTime, ...);
// only SpringBoard knows, so ask it. If it doesn't answer, sample anyway.
static void (^frontAppCompletion)(BOOL blocked);
static NSUInteger frontAppGeneration;

static void finishFrontAppQuery(BOOL blocked) {
	void (^completion)(BOOL) = frontAppCompletion;
	frontAppCompletion = nil;
	frontAppGeneration++;
	if (completion)
		completion(blocked);
}

static void queryFrontApp(void (^completion)(BOOL blocked)) {
	frontAppCompletion = [completion copy];
	NSUInteger generation = ++frontAppGeneration;
	notify_post(QD_FRONT_APP_QUERY);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (generation == frontAppGeneration) {
			QDDebugLog(@"SpringBoard did not say which app is in front, sampling anyway");
			finishFrontAppQuery(NO);
		}
	});
}

static void regularSample(void) {
	if (!tweakEnabled() || pillActive || screenOffOrLocked()) {
		QDDebugLog(@"skipping the sample (enabled %d, pill %d, screen off or locked %d)", tweakEnabled(), pillActive, screenOffOrLocked());
		scheduleNextSample(QD16_SAMPLE_INTERVAL);
		return;
	}
	queryFrontApp(^(BOOL blocked) {
		if (blocked) {
			QDDebugLog(@"skipping the sample, the front app is one iOS never samples in");
			scheduleNextSample(QD16_SAMPLE_INTERVAL);
			return;
		}
		takeCountedSample();
	});
}

static void takeCountedSample(void) {
	takeSample(^(BOOL ok, BOOL face, double distance) {
		if (ok)
			applySample(face, distance);
		if (ok && tooCloseCount >= QD16_STOCK_SENSITIVITY) {
			tooCloseCount = 0;
#if QD16_DRY_RUN
			QDDebugLog(@"too-close count reached %.0f: would show the pill (dry run)", QD16_STOCK_SENSITIVITY);
#else
			startPill();
#endif
		}
		scheduleNextSample(QD16_SAMPLE_INTERVAL);
	});
}

static void scheduleNextSample(NSTimeInterval delay) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		regularSample();
	});
}

#pragma mark - Hooks

%group backboardd16

%hook AWPearlAttentionSampler
- (id)init {
	id sampler = %orig;
	pearlSampler = sampler;
	QDDebugLog(@"captured AWPearlAttentionSampler %@", sampler);
	return sampler;
}
%end

%end

static void triggerWarning(QDPillRequest request) {
	if (pillActive) {
		QDDebugLog(@"trigger ignored, warning already up");
		return;
	}
	nextPillRequest = request;
	QDDebugLog(@"showing warning on request");
	startPill();
}

%ctor {
	if (![[[NSProcessInfo processInfo] processName] isEqualToString:@"backboardd"])
		return;
	// iOS 17 has the real thing, Daemon.x handles it
	if ([NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}])
		return;

	// backboardd loads these lazily
	dlopen("/System/Library/PrivateFrameworks/AttentionAwareness.framework/AttentionAwareness", RTLD_NOW);
	dlopen("/System/Library/PrivateFrameworks/BiometricKit.framework/BiometricKit", RTLD_NOW);
	if (!objc_getClass("AWPearlAttentionSampler") || !objc_getClass("BKFaceDetectOperation")) {
		QDDebugLog(@"AttentionAwareness / BiometricKit classes missing, not starting");
		return;
	}
	%init(backboardd16);

	int token;
	notify_register_dispatch(QD_TRIGGER, &token, dispatch_get_main_queue(), ^(int t) {
		QDDebugLog(@"trigger received");
		notify_post(QD_TRIGGER_ACK);
		triggerWarning(QDPillRequestIgnoreRules | QDPillRequestTest);
	});
	notify_register_dispatch(QD_TRIGGER_DELAYED, &token, dispatch_get_main_queue(), ^(int t) {
		QDDebugLog(@"delayed trigger received, showing in %d s", QD_DELAYED_TEST_SECONDS);
		notify_post(QD_TRIGGER_ACK);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, QD_DELAYED_TEST_SECONDS * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			triggerWarning(QDPillRequestTest);
		});
	});
	notify_register_dispatch(QD_FRONT_APP_REPLY, &token, dispatch_get_main_queue(), ^(int t) {
		static int stateToken = NOTIFY_TOKEN_INVALID;
		finishFrontAppQuery(QDReadState(QD_FRONT_APP_STATE, &stateToken) == 1);
	});
	notify_register_dispatch(QD_PILL_DISMISSED, &token, dispatch_get_main_queue(), ^(int t) {
		finishPill(NO, @"SpringBoard took it down");
	});
	notify_register_dispatch(QD_PILL_SUPPRESSED, &token, dispatch_get_main_queue(), ^(int t) {
		finishPill(NO, @"SpringBoard did not show it (excluded app or excluded time)");
	});

	scheduleNextSample(QD16_FIRST_SAMPLE_DELAY);
	QDDebugLog(@"loaded into backboardd (iOS 16 backend, dry run %d), threshold %ld mm, sensitivity %.0f samples",
		QD16_DRY_RUN, (long)thresholdMillimeters(), sensitivitySamples());
}
