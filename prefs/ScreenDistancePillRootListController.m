#import "ScreenDistancePillRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../ScreenDistancePillPrefs.h"
#import "../ScreenDistancePillLog.h"
#include <dlfcn.h>
#include <notify.h>
#include <roothide.h>
#include <spawn.h>
#include <signal.h>
#include <errno.h>
#include <sys/wait.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

extern char **environ;

#define QDLogCopyMaxBytes (200 * 1024)

// Kills every process called name with kill(2). Returns how many were found;
// failure gets a short reason when one of them could not be killed.
static int QDKillByName(NSString *name, NSString **failure) {
	int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
	size_t size = 0;
	if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0) {
		*failure = [NSString stringWithFormat:@"sysctl failed: %s", strerror(errno)];
		return -1;
	}
	struct kinfo_proc *procs = malloc(size);
	if (sysctl(mib, 3, procs, &size, NULL, 0) != 0) {
		free(procs);
		*failure = [NSString stringWithFormat:@"sysctl failed: %s", strerror(errno)];
		return -1;
	}
	int found = 0;
	for (size_t i = 0; i < size / sizeof(struct kinfo_proc); i++) {
		if (strcmp(procs[i].kp_proc.p_comm, name.UTF8String) != 0)
			continue;
		found++;
		if (kill(procs[i].kp_proc.p_pid, SIGKILL) != 0)
			*failure = [NSString stringWithFormat:@"kill(%d) failed: %s", procs[i].kp_proc.p_pid, strerror(errno)];
	}
	free(procs);
	return found;
}

// fallback when kill(2) is refused: killall from the jailbreak root
static BOOL QDKillall(NSString *name) {
	NSString *path = jbroot(@"/usr/bin/killall");
	if (![[NSFileManager defaultManager] isExecutableFileAtPath:path])
		return NO;
	char *argv[] = { (char *)path.fileSystemRepresentation, "-9", (char *)name.UTF8String, NULL };
	pid_t pid;
	int status = 0;
	if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0)
		return NO;
	waitpid(pid, &status, 0);
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

// EyeRelief.framework's XPC client for com.apple.eyereliefd
@interface EREyeReliefClient : NSObject
- (BOOL)isDistanceSamplingEnabledWithError:(NSError **)error;
@end

@implementation QDListController

static BOOL isOurs(PSSpecifier *specifier) {
	return [specifier.properties[@"defaults"] isEqualToString:@"com.qn.screendistancepill"]
		&& specifier.properties[@"key"] != nil;
}

// Root.plist is an old-style plist, where every value is a string.
// PSSliderTableCell treats min / max / segmentCount / default as NSNumbers and
// crashes on strings, so turn them into numbers once they are loaded.
static void numberifySliderProperties(NSArray<PSSpecifier *> *specifiers) {
	for (PSSpecifier *specifier in specifiers) {
		if (specifier.cellType != PSSliderCell)
			continue;
		for (NSString *key in @[ @"min", @"max", @"default", @"segmentCount" ]) {
			id value = specifier.properties[key];
			if ([value isKindOfClass:[NSString class]])
				[specifier setProperty:@([value doubleValue]) forKey:key];
		}
	}
}

// AltList is loaded with dlopen(jbroot(...)) rather than linked (as in
// PerAppKeyboard), so the page still opens without it, just without the app
// picker. Must run before the specifiers load: the Excluded Apps row names its
// detail class.
static BOOL loadAltList(void) {
	static dispatch_once_t once;
	static BOOL available;
	dispatch_once(&once, ^{
		if (!NSClassFromString(@"ATLApplicationListMultiSelectionController")) {
			NSString *path = jbroot(@"/Library/Frameworks/AltList.framework/AltList");
			if (!dlopen(path.fileSystemRepresentation, RTLD_NOW))
				QDLog(@"couldn't load AltList from %@: %s", path, dlerror());
		}
		available = NSClassFromString(@"ATLApplicationListMultiSelectionController") != nil;
	});
	return available;
}

// rows that only matter while a switch is on, by the switch's key
static NSDictionary<NSString *, NSArray<NSString *> *> *dependentRows(void) {
	return @{
		@"pillHaptic": @[ @"pillHapticStrength" ],
		@"pauseEnabled": @[ @"pauseStart", @"pauseEnd" ],
	};
}

- (NSString *)plistName {
	return nil;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [[self loadSpecifiersFromPlistName:[self plistName] target:self] mutableCopy];
		numberifySliderProperties(specifiers);
		_specifiers = specifiers;
		NSDictionary *prefs = [QDPrefs load];
		[dependentRows() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray<NSString *> *rows, BOOL *stop) {
			[self setRowsWithIDs:rows enabled:[prefs[key] boolValue] reload:NO];
		}];
	}
	return _specifiers;
}

// footer notes justified on every page. Depending on the iOS version the
// footer draws through a content configuration or the older textLabel, so
// set both.
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:_cmd])
		[super tableView:tableView willDisplayFooterView:view forSection:section];
	if (![view isKindOfClass:[UITableViewHeaderFooterView class]])
		return;
	UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
	if ([footer.contentConfiguration isKindOfClass:[UIListContentConfiguration class]]) {
		UIListContentConfiguration *config = [(UIListContentConfiguration *)footer.contentConfiguration copy];
		config.textProperties.alignment = UIListContentTextAlignmentJustified;
		footer.contentConfiguration = config;
	} else {
		footer.textLabel.textAlignment = NSTextAlignmentJustified;
	}
}

// dim rows that only matter while a switch is on, like FlicksForAll does.
// Rows that are on another page are simply not found.
- (void)setRowsWithIDs:(NSArray<NSString *> *)identifiers enabled:(BOOL)enabled reload:(BOOL)reload {
	for (NSString *identifier in identifiers) {
		PSSpecifier *row = [self specifierForID:identifier];
		if (!row)
			continue;
		[row setProperty:@(enabled) forKey:@"enabled"];
		if (reload)
			[self reloadSpecifier:row animated:YES];
	}
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if (!isOurs(specifier))
		return [super readPreferenceValue:specifier];

	return [QDPrefs load][specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if (!isOurs(specifier)) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}

	NSString *key = specifier.properties[@"key"];
	[QDPrefs setObject:value forKey:key];
	NSArray<NSString *> *rows = dependentRows()[key];
	if (rows)
		[self setRowsWithIDs:rows enabled:[value boolValue] reload:YES];
}

@end

@implementation QDSensitivityListController

- (NSString *)plistName {
	return @"Sensitivity";
}

@end

@implementation QDAppearanceListController

- (NSString *)plistName {
	return @"Appearance";
}

@end

@implementation QDExcludeListController

- (NSString *)plistName {
	return @"Exclude";
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		BOOL altList = loadAltList();
		[super specifiers];
		if (!altList) {
			[[self specifierForID:@"excludedApps"] setProperty:@NO forKey:@"enabled"];
			[[self specifierForID:@"excludedAppsGroup"] setProperty:@"Choosing apps needs AltList (com.opa334.altlist). Install it, then reopen this page." forKey:@"footerText"];
		}
	}
	return _specifiers;
}

// AltList's multi-selection list reads and writes the bundle ids through the
// Excluded Apps row's getter and setter
- (NSArray *)excludedApps:(PSSpecifier *)specifier {
	NSArray *apps = [QDPrefs load][@"excludedApps"];
	return [apps isKindOfClass:[NSArray class]] ? apps : @[];
}

- (void)setExcludedApps:(NSArray *)apps specifier:(PSSpecifier *)specifier {
	[QDPrefs setObject:[apps isKindOfClass:[NSArray class]] ? apps : @[] forKey:@"excludedApps"];
}

@end

@implementation QDRootListController

- (NSString *)plistName {
	return @"Root";
}

// eyereliefd relaunches on its next mach lookup or XPC activity, and the fresh
// process picks up the tweak (or drops it).
- (void)killProcess:(NSString *)name {
	NSString *failure = nil;
	int found = QDKillByName(name, &failure);
	NSString *title;
	NSString *message = nil;
	if (found == 0) {
		title = [NSString stringWithFormat:@"%@ is not running", name];
		message = @"It will load the current version of ScreenDistancePill when it starts.";
	} else if (failure == nil || QDKillall(name)) {
		title = [NSString stringWithFormat:@"%@ restarted", name];
	} else {
		title = [NSString stringWithFormat:@"Could not restart %@", name];
		message = failure;
	}
	[self showAlertWithTitle:title message:message];
}

- (void)restartEyeReliefDaemon {
	[self killProcess:@"eyereliefd"];
}

- (void)openSourceCode:(PSSpecifier *)specifier {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/qnblackcat/ScreenDistancePill"] options:@{} completionHandler:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)copyDebugLog {
	NSString *log = QDLogFileRead(QDLogCopyMaxBytes);
	if (!log.length) {
		[self showAlertWithTitle:@"Debug log is empty" message:@"Turn on Debug, then show the warning with the test button."];
		return;
	}
	struct utsname system;
	uname(&system);
	NSString *header = [NSString stringWithFormat:@"ScreenDistancePill debug log, iOS %@, %s\n", [UIDevice currentDevice].systemVersion, system.machine];
	[UIPasteboard generalPasteboard].string = [header stringByAppendingString:log];
	[self showAlertWithTitle:@"Copied" message:[NSString stringWithFormat:@"%lu KB of debug log copied to the clipboard.", (unsigned long)(log.length / 1024 + 1)]];
}

- (void)clearDebugLog {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear debug log?" message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		QDLogFileClear();
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset all settings?" message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[QDPrefs reset];
		[self reloadSpecifiers];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

// set when eyereliefd acknowledges the last trigger
static BOOL triggerAcked;

- (void)triggerWarning:(PSSpecifier *)specifier {
	[self postTrigger:QD_TRIGGER];
}

- (void)triggerWarningDelayed:(PSSpecifier *)specifier {
	[self postTrigger:QD_TRIGGER_DELAYED];
}

- (void)postTrigger:(const char *)name {
	static int ackToken = NOTIFY_TOKEN_INVALID;
	if (ackToken == NOTIFY_TOKEN_INVALID) {
		notify_register_dispatch(QD_TRIGGER_ACK, &ackToken, dispatch_get_main_queue(), ^(int t) {
			QDDebugLog(@"eyereliefd acknowledged the trigger");
			triggerAcked = YES;
		});
	}
	triggerAcked = NO;

	// eyereliefd is launched on demand and exits when idle, so talk to its mach
	// service first; launchd starts it if needed and the reply means it is up.
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *wakeResult;
		void *handle = dlopen("/System/Library/PrivateFrameworks/EyeRelief.framework/EyeRelief", RTLD_LAZY);
		Class clientClass = NSClassFromString(@"EREyeReliefClient");
		if (!handle || !clientClass) {
			wakeResult = [NSString stringWithFormat:@"EyeRelief client unavailable (%s)", dlerror() ?: "class missing"];
		} else {
			NSError *error = nil;
			BOOL sampling = [[clientClass new] isDistanceSamplingEnabledWithError:&error];
			wakeResult = error
				? [NSString stringWithFormat:@"XPC error: %@", error]
				: [NSString stringWithFormat:@"XPC ok, distance sampling %@", sampling ? @"on" : @"off"];
		}
		QDDebugLog(@"waking eyereliefd: %@", wakeResult);
		uint32_t status = notify_post(name);
		QDDebugLog(@"posted trigger, status %u", status);

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			if (triggerAcked)
				return;
			UIAlertController *alert = [UIAlertController
				alertControllerWithTitle:@"eyereliefd didn't respond"
				message:[NSString stringWithFormat:@"%@\nnotify_post status: %u\n\nThe tweak is probably not loaded into eyereliefd.", wakeResult, status]
				preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:alert animated:YES completion:nil];
		});
	});
}

@end
