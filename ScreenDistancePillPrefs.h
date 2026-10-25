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
// too-close threshold in mm
#define QD_THRESHOLD_STATE "com.qn.screendistancepill/Threshold"
// too-close samples (80 s apart) before a reminder; iOS uses 4
#define QD_SENSITIVITY_STATE "com.qn.screendistancepill/Sensitivity"

// defaults, also in Root.plist
#define QD_DEFAULT_DISTANCE_CM 30
#define QD_DEFAULT_SENSITIVITY 4
#define QD_DEFAULT_PAUSE_START (22 * 60)
#define QD_DEFAULT_PAUSE_END (7 * 60)

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
