#import <Foundation/Foundation.h>

#define QD_PREFS_CHANGED "com.qn.screendistancepill/ReloadPrefs"
// test buttons in Settings, handled by eyereliefd. Trigger shows the pill at
// once and ignores excluded apps and the pause schedule; TriggerDelayed waits
// QD_DELAYED_TEST_SECONDS and then goes through them like a real reminder.
#define QD_TRIGGER "com.qn.screendistancepill/Trigger"
#define QD_TRIGGER_DELAYED "com.qn.screendistancepill/TriggerDelayed"
#define QD_DELAYED_TEST_SECONDS 5
// posted back by eyereliefd as soon as it receives a trigger
#define QD_TRIGGER_ACK "com.qn.screendistancepill/TriggerAck"

// eyereliefd asks SpringBoard to show / hide the pill; SpringBoard tells
// eyereliefd when it took the pill down on its own (lock, timeout) or did not
// show it at all (excluded app, pause schedule).
// PillShow carries QDPillRequest flags as its notify state.
#define QD_PILL_SHOW "com.qn.screendistancepill/PillShow"
// PillHide: the face is far enough away (the pill flashes a check mark first);
// PillCancel: eyereliefd gave up (sample failed, timeout), just fade it out
#define QD_PILL_HIDE "com.qn.screendistancepill/PillHide"
#define QD_PILL_CANCEL "com.qn.screendistancepill/PillCancel"
#define QD_PILL_DISMISSED "com.qn.screendistancepill/PillDismissed"
#define QD_PILL_SUPPRESSED "com.qn.screendistancepill/PillSuppressed"

typedef NS_OPTIONS(uint64_t, QDPillRequest) {
	// show even in an excluded app or during the pause schedule
	QDPillRequestIgnoreRules = 1 << 0,
	// a test run, only marked as such in the log
	QDPillRequestTest = 1 << 1,
};

// Notify states published by SpringBoard, which can always read the plist;
// eyereliefd's sandbox might not.
// QDEnabledState; 0 means SpringBoard hasn't published it, which counts as on
// (the setting's default) so the tweak never silently falls back to stock
#define QD_ENABLED_STATE "com.qn.screendistancepill/Enabled"
typedef NS_ENUM(uint64_t, QDEnabledState) {
	QDEnabledStateUnknown = 0,
	QDEnabledStateOn = 1,
	QDEnabledStateOff = 2,
};
// 1 while Debug is on
#define QD_DEBUG_STATE "com.qn.screendistancepill/Debug"
// too-close threshold in mm; 0 (Custom Sensitivity off) means iOS's own
#define QD_THRESHOLD_STATE "com.qn.screendistancepill/Threshold"
// too-close samples (80 s apart) before a reminder; 0 (Custom Sensitivity
// off) means iOS's own 4
#define QD_SENSITIVITY_STATE "com.qn.screendistancepill/Sensitivity"

// a notify state, registering name into *token (NOTIFY_TOKEN_INVALID at
// first) on the first call; 0 if it can't be read
uint64_t QDReadState(const char *name, int *token);

// the "defaults" of every row in the Settings plists
#define QD_PREFS_DOMAIN @"com.qn.screendistancepill"

// keys in the plist
#define QD_KEY_ENABLED @"enabled"
#define QD_KEY_DEBUG @"debug"
// 👁️ Warning Sensitivity
#define QD_KEY_SENSITIVITY_ENABLED @"sensitivityEnabled"
#define QD_KEY_DISTANCE_CM @"distanceCm"
#define QD_KEY_SENSITIVITY @"sensitivity"
// 🎨 Appearance
#define QD_KEY_FADE_DURATION @"pillShowDuration"
#define QD_KEY_CHECK_HOLD @"pillCheckHold"
#define QD_KEY_EDGE_GLOW @"pillEdgeGlow"
#define QD_KEY_EDGE_GLOW_DELAY @"pillEdgeGlowDelay"
#define QD_KEY_GLOW @"pillGlow"
#define QD_KEY_GLOW_STRENGTH @"pillGlowStrength"
#define QD_KEY_BOUNCE @"pillBounce"
#define QD_KEY_HAPTIC @"pillHaptic"
#define QD_KEY_HAPTIC_STRENGTH @"pillHapticStrength"
// 🚫 Exclude
#define QD_KEY_EXCLUDED_APPS @"excludedApps"
#define QD_KEY_PAUSE_ENABLED @"pauseEnabled"
#define QD_KEY_PAUSE_START @"pauseStart"
#define QD_KEY_PAUSE_END @"pauseEnd"

// defaults, also in the Settings plists (Root, Sensitivity, Appearance,
// Exclude); keep both in step
#define QD_DEFAULT_ENABLED YES
#define QD_DEFAULT_DEBUG NO
#define QD_DEFAULT_SENSITIVITY_ENABLED NO
#define QD_DEFAULT_DISTANCE_CM 30
#define QD_DEFAULT_SENSITIVITY 4
#define QD_DEFAULT_FADE_DURATION 0.6
#define QD_DEFAULT_CHECK_HOLD 1.2
#define QD_DEFAULT_EDGE_GLOW NO
#define QD_DEFAULT_EDGE_GLOW_DELAY 15
#define QD_DEFAULT_GLOW YES
#define QD_DEFAULT_GLOW_STRENGTH 100
#define QD_DEFAULT_BOUNCE YES
#define QD_DEFAULT_HAPTIC NO
#define QD_DEFAULT_HAPTIC_STRENGTH @"light"
#define QD_DEFAULT_PAUSE_ENABLED NO
#define QD_DEFAULT_PAUSE_START (22 * 60)
#define QD_DEFAULT_PAUSE_END (7 * 60)

// a stored switch, or fallback when it is missing or not a number
BOOL QDPrefBool(NSDictionary *prefs, NSString *key, BOOL fallback);
// a stored number (slider, segment), or fallback when it is missing or not a
// number; clamped to [min, max]
double QDPrefDouble(NSDictionary *prefs, NSString *key, double fallback, double min, double max);

// Settings live in one plist inside jbroot instead of going through cfprefsd,
// which would deny our domain to sandboxed processes (same trick as
// FlicksForAll).
@interface QDPrefs : NSObject
+ (NSString *)path;
+ (NSDictionary *)load;
// posts QD_PREFS_CHANGED after writing; a nil value removes the key
+ (void)setObject:(id)value forKey:(NSString *)key;
// deletes the plist so every setting is back to its default, then posts
// QD_PREFS_CHANGED
+ (void)reset;
@end
