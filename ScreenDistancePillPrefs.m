#import "ScreenDistancePillPrefs.h"
#import "ScreenDistancePillLog.h"
#include <roothide.h>
#include <notify.h>

uint64_t QDReadState(const char *name, int *token) {
	if (*token == NOTIFY_TOKEN_INVALID && notify_register_check(name, token) != NOTIFY_STATUS_OK)
		return 0;
	uint64_t state = 0;
	notify_get_state(*token, &state);
	return state;
}

// segment cells store their values as strings, sliders and switches as numbers
static id QDPrefNumber(NSDictionary *prefs, NSString *key) {
	id value = prefs[key];
	return [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]] ? value : nil;
}

BOOL QDPrefBool(NSDictionary *prefs, NSString *key, BOOL fallback) {
	id value = QDPrefNumber(prefs, key);
	return value ? [value boolValue] : fallback;
}

double QDPrefDouble(NSDictionary *prefs, NSString *key, double fallback, double min, double max) {
	id value = QDPrefNumber(prefs, key);
	double number = value ? [value doubleValue] : fallback;
	return MIN(MAX(number, min), max);
}

@implementation QDPrefs

+ (NSString *)path {
	return jbroot([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", QD_PREFS_DOMAIN]);
}

+ (NSDictionary *)load {
	return [NSDictionary dictionaryWithContentsOfFile:[self path]] ?: @{};
}

+ (void)setObject:(id)value forKey:(NSString *)key {
	NSMutableDictionary *prefs = [[self load] mutableCopy];
	prefs[key] = value;
	NSString *path = [self path];
	[[NSFileManager defaultManager]
		createDirectoryAtPath:[path stringByDeletingLastPathComponent]
		withIntermediateDirectories:YES
		attributes:nil
		error:NULL];
	if (![prefs writeToFile:path atomically:YES])
		QDDebugLog(@"couldn't write preferences to %@", path);
	notify_post(QD_PREFS_CHANGED);
}

+ (void)reset {
	NSError *error = nil;
	if (![[NSFileManager defaultManager] removeItemAtPath:[self path] error:&error] && error.code != NSFileNoSuchFileError)
		QDDebugLog(@"couldn't remove preferences at %@: %@", [self path], error);
	notify_post(QD_PREFS_CHANGED);
}

@end
