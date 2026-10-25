#import "ScreenDistancePillPrefs.h"
#import "ScreenDistancePillLog.h"
#include <roothide.h>
#include <notify.h>

@implementation QDPrefs

+ (NSString *)path {
	return jbroot(@"/var/mobile/Library/Preferences/com.qn.screendistancepill.plist");
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
		QDLog(@"couldn't write preferences to %@", path);
	notify_post(QD_PREFS_CHANGED);
}

+ (void)reset {
	NSError *error = nil;
	if (![[NSFileManager defaultManager] removeItemAtPath:[self path] error:&error] && error.code != NSFileNoSuchFileError)
		QDLog(@"couldn't remove preferences at %@: %@", [self path], error);
	notify_post(QD_PREFS_CHANGED);
}

@end
