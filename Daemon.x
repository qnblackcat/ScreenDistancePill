// Runs inside eyereliefd.
//
// The daemon samples the face distance every 80 s. Each too-close sample adds
// 1 to -[EREyeReliefEngine tooCloseCount] (a normal one takes 1 off), and at 4
// it calls -[ERDaemonManager interveneWithType:withCompletion:], which shows
// the full-screen shield through a remote alert. While the tweak is enabled:
// - that method is replaced: SpringBoard shows a pill instead (Pill.x), and the
//   daemon keeps sampling until the face is far enough away (or gone), then
//   hides the pill and reports the outcome EyeReliefUI gives when Continue is
//   tapped at a safe distance. If SpringBoard declines to show it (excluded
//   app / time) it ends the same way.
// - the too-close threshold and the number of too-close samples before a
//   reminder come from Settings.
// Disabled, everything is stock. The test buttons in Settings run the same path.

#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import "ScreenDistancePillPrefs.h"
#import "ScreenDistancePillLog.h"

// EyeReliefUI.InterventionType: None = 0, Shield = 1, Notice = 2
#define QD_INTERVENTION_SHIELD 1
// what eyereliefd receives when the shield closes at a safe distance
#define QD_OUTCOME_SAFE_DISTANCE 2
// ERDistanceEvent.distanceCategory, from
// +[ERAttentionAwarenessClient _categoryForDistance:withTooCloseDistanceThreshold:withFaceState:]:
// 0 too close, 1 at or beyond the threshold, 2 no face
#define QD_DISTANCE_TOO_CLOSE 0
#define QD_PILL_SAMPLE_INTERVAL 0.3
// give up and take the pill down after this long no matter what
#define QD_PILL_MAX_DURATION 180
// tooCloseCount at which the engine asks for an intervention
#define QD_STOCK_SENSITIVITY 4.0f

@interface ERDistanceEvent : NSObject
@property (nonatomic) float distance;
@property (nonatomic) NSInteger distanceCategory;
@end

@interface EREyeReliefEngine : NSObject
@property (nonatomic) float tooCloseCount;
- (void)takeDistanceSampleWithCompletion:(void (^)(ERDistanceEvent *event, NSInteger interventionType))completion;
@end

@interface ERDaemonManager : NSObject
@property (nonatomic, strong) EREyeReliefEngine *engine;
- (void)interveneWithType:(NSInteger)type withCompletion:(void (^)(NSInteger outcome))completion;
@end

@interface ERAttentionAwarenessClient : NSObject
@end

static __weak ERDaemonManager *daemonManager;
static BOOL triggerInFlight;

// settings SpringBoard publishes as notify states; 0 means not published
static uint64_t readState(const char *name, int *token) {
	if (*token == NOTIFY_TOKEN_INVALID && notify_register_check(name, token) != NOTIFY_STATUS_OK)
		return 0;
	uint64_t state = 0;
	notify_get_state(*token, &state);
	return state;
}

// the state if it lies in [min, max], else 0
static uint64_t readStateInRange(const char *name, int *token, uint64_t min, uint64_t max) {
	uint64_t state = readState(name, token);
	return state >= min && state <= max ? state : 0;
}

static BOOL tweakEnabled(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	return readState(QD_ENABLED_STATE, &token) != QDEnabledStateOff;
}

static NSInteger thresholdMillimeters(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	uint64_t mm = readStateInRange(QD_THRESHOLD_STATE, &token, 200, 500);
	return mm ?: QD_DEFAULT_DISTANCE_CM * 10;
}

static float sensitivitySamples(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	uint64_t samples = readStateInRange(QD_SENSITIVITY_STATE, &token, 1, 20);
	return samples ?: QD_STOCK_SENSITIVITY;
}

// the threshold both the engine and the client compare against
static NSInteger effectiveThreshold(NSInteger stock) {
	return tweakEnabled() ? thresholdMillimeters() : stock;
}

// all pill state lives on the main queue
static BOOL pillActive;
static NSUInteger pillGeneration;
static void (^pillCompletion)(NSInteger outcome);
// flags for the next pill, set by the test buttons; real reminders use none
static QDPillRequest nextPillRequest;

// distanceFine: the last sample was at a safe distance (or showed no face)
static void finishPill(BOOL distanceFine, NSString *reason) {
	if (!pillActive)
		return;
	pillActive = NO;
	pillGeneration++;
	notify_post(distanceFine ? QD_PILL_HIDE : QD_PILL_CANCEL);
	QDDebugLog(@"pill down: %@", reason);
	void (^completion)(NSInteger) = pillCompletion;
	pillCompletion = nil;
	if (completion)
		completion(QD_OUTCOME_SAFE_DISTANCE);
}

static void samplePillDistance(ERDaemonManager *manager, NSUInteger generation) {
	if (!pillActive || generation != pillGeneration)
		return;
	CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
	[manager.engine takeDistanceSampleWithCompletion:^(ERDistanceEvent *event, NSInteger interventionType) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!pillActive || generation != pillGeneration)
				return;
			QDDebugLog(@"sample took %.0f ms: %@", (CFAbsoluteTimeGetCurrent() - started) * 1000,
				event ? [NSString stringWithFormat:@"%.0f mm, category %ld", event.distance, (long)event.distanceCategory] : @"no event");
			if (!event) {
				finishPill(NO, @"distance sample failed");
				return;
			}
			if (event.distanceCategory != QD_DISTANCE_TOO_CLOSE) {
				finishPill(YES, @"safe distance");
				return;
			}
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QD_PILL_SAMPLE_INTERVAL * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				samplePillDistance(manager, generation);
			});
		});
	}];
}

static void startPill(ERDaemonManager *manager, void (^completion)(NSInteger)) {
	QDPillRequest request = nextPillRequest;
	nextPillRequest = 0;
	if (pillActive) {
		// shouldn't happen: the daemon waits for the outcome before sampling again
		QDDebugLog(@"pill already up, closing the new request at once");
		if (completion)
			completion(QD_OUTCOME_SAFE_DISTANCE);
		return;
	}
	pillActive = YES;
	NSUInteger generation = ++pillGeneration;
	pillCompletion = [completion copy];
	QDDebugLog(@"asking SpringBoard for the pill (flags %llu, threshold %ld mm)", (unsigned long long)request, (long)thresholdMillimeters());

	static int showToken = NOTIFY_TOKEN_INVALID;
	if (showToken == NOTIFY_TOKEN_INVALID)
		notify_register_check(QD_PILL_SHOW, &showToken);
	notify_set_state(showToken, request);
	notify_post(QD_PILL_SHOW);

	samplePillDistance(manager, generation);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, QD_PILL_MAX_DURATION * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (generation == pillGeneration)
			finishPill(NO, @"timed out");
	});
}

// set while the engine handles one distance sample, so only its own
// increments get scaled
static BOOL processingSample;
// bumped per test warning so an old timeout can't clear a newer warning's flag
static NSUInteger triggerGeneration;

%group eyereliefd

%hook ERDaemonManager
- (instancetype)init {
	self = %orig;
	daemonManager = self;
	QDDebugLog(@"captured ERDaemonManager %@", self);
	return self;
}

- (void)interveneWithType:(NSInteger)type withCompletion:(void (^)(NSInteger outcome))completion {
	if (!tweakEnabled()) {
		%orig;
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		startPill(self, completion);
	});
}
%end

%hook EREyeReliefEngine
- (NSInteger)tooCloseDistanceThreshold {
	return effectiveThreshold(%orig);
}

- (void)_processDistanceEvent:(id)event {
	processingSample = YES;
	%orig;
	processingSample = NO;
}

// Sensitivity: a too-close sample adds 4 / N instead of 1, so the engine's
// fixed limit of 4 is reached after N samples.
- (void)setTooCloseCount:(float)count {
	float old = self.tooCloseCount;
	float stock = count;
	if (processingSample && tweakEnabled() && count > old)
		count = old + (count - old) * QD_STOCK_SENSITIVITY / sensitivitySamples();
	if (processingSample)
		QDDebugLog(@"too-close count %.2f -> %.2f (stock %.2f)", old, count, stock);
	%orig(count);
}
%end

%hook ERAttentionAwarenessClient
- (NSInteger)tooCloseDistanceThreshold {
	return effectiveThreshold(%orig);
}
%end

%end

static void triggerWarning(QDPillRequest request) {
	ERDaemonManager *manager = daemonManager;
	if (!manager) {
		QDDebugLog(@"trigger ignored, no ERDaemonManager yet");
		return;
	}
	if (triggerInFlight || pillActive) {
		QDDebugLog(@"trigger ignored, warning already up");
		return;
	}
	triggerInFlight = YES;
	NSUInteger generation = ++triggerGeneration;
	nextPillRequest = request;
	QDDebugLog(@"showing warning on request");
	void (^unlock)(void) = ^{
		if (generation == triggerGeneration)
			triggerInFlight = NO;
	};
	// The outcome is deliberately not handed to the engine: a test run should
	// not count towards the daemon's too-close bookkeeping.
	[manager interveneWithType:QD_INTERVENTION_SHIELD withCompletion:^(NSInteger outcome) {
		QDDebugLog(@"test warning closed with outcome %ld", (long)outcome);
		dispatch_async(dispatch_get_main_queue(), unlock);
	}];
	// don't stay locked out if the remote alert never reports back
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), unlock);
}

%ctor {
	if (![[[NSProcessInfo processInfo] processName] isEqualToString:@"eyereliefd"])
		return;

	%init(eyereliefd);

	int token;
	uint32_t status = notify_register_dispatch(QD_TRIGGER, &token, dispatch_get_main_queue(), ^(int t) {
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
	notify_register_dispatch(QD_PILL_DISMISSED, &token, dispatch_get_main_queue(), ^(int t) {
		finishPill(NO, @"SpringBoard took it down");
	});
	notify_register_dispatch(QD_PILL_SUPPRESSED, &token, dispatch_get_main_queue(), ^(int t) {
		finishPill(NO, @"SpringBoard did not show it (excluded app or excluded time)");
	});
	QDDebugLog(@"loaded into eyereliefd, notify_register status %u, enabled %d, threshold %ld mm, sensitivity %.0f samples",
		status, tweakEnabled(), (long)thresholdMillimeters(), sensitivitySamples());
}
