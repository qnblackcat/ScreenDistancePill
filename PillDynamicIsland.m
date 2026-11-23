// Dynamic Island mode: shows the "too close" warning as an element in
// SpringBoard's System Aperture (the Dynamic Island) instead of the pill, and
// swaps its icon for a check mark when the phone is far enough away.
//
// All of it is private and was worked out on iOS 17, so every class is looked
// up by name and anything missing just means the pill is used instead.
// Runs inside SpringBoard.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ScreenDistancePillLog.h"
#import "ScreenDistancePillPrefs.h"
#import "PillDynamicIsland.h"

@interface UIWindowScene (QDIsland)
- (id)systemApertureController;
@end

@interface NSObject (QDIsland)
- (id)initWithClientIdentifier:(NSString *)clientIdentifier elementIdentifier:(NSString *)elementIdentifier;
- (id)initWithIdentifier:(id)identification contentProvider:(id)contentProvider;
- (void)setLeadingContentViewProvider:(id)provider;
- (void)setMinimalContentViewProvider:(id)provider;
- (id)initWithView:(UIView *)view;
- (void)setTrailingContentViewProvider:(id)provider;
- (void)setMinimumSupportedLayoutMode:(long long)mode;
- (void)setMaximumSupportedLayoutMode:(long long)mode;
- (void)setPreferredLayoutMode:(long long)mode;
- (id)registerElement:(id)element;
- (void)invalidateWithReason:(NSString *)reason;
@end

// the assertion that keeps the element in the island, and the two icon views
// in it (the leading picture, then the minimal icon)
static id islandAssertion;
static NSArray<UIImageView *> *islandIconViews;

// Sizes, in points. The island lays out relative to its capsule, so these are
// not tied to a screen resolution.
//
// How far the element reaches out on its leading side in layout mode 1. The
// island asks about mode 1 for the wide capsule on the left (it suggests about
// 30) and for the small bubble on the right (about 34), and the container is
// exactly this wide either way. 44 is the stock bubble's width and leaves the
// icon room on the left, where a wider value would push the bubble into the
// status bar's icons on the right.
#define QD_ISLAND_LEADING_OUTSET 44
// Alone in the island (layout mode 2) the system suggests about 50 on the
// leading side and 26 on the trailing side. Both are more than needed.
#define QD_ISLAND_ALONE_LEADING 38
#define QD_ISLAND_ALONE_TRAILING 14
// The leading picture: the icon at the left end of a transparent rectangle,
// with a margin so it clears the capsule's round end. The island cuts off
// whatever reaches past the camera, so the icon must stay at the far left.
#define QD_ISLAND_LEADING_SIZE CGSizeMake(QD_ISLAND_LEADING_OUTSET, 25)
#define QD_ISLAND_LEADING_MARGIN 2
#define QD_ISLAND_LEADING_ICON_HEIGHT 19
// The minimal icon, in the small bubble next to the island when two things
// are active. The bubble is as wide as this view plus its padding (about 11 pt
// each side), so anything wider than the stock bubble's 22 pt icon makes it
// grow into the status bar's icons.
#define QD_ISLAND_MINIMAL_SIZE CGSizeMake(22, 22)
#define QD_ISLAND_MINIMAL_ICON_HEIGHT 15

// The stock element, plus our own edge outsets. Made on first use.
static Class islandElementClass(Class base) {
	static Class subclass;
	if (subclass)
		return subclass;
	subclass = objc_allocateClassPair(base, "QDIslandElement", 0);
	if (!subclass)
		return base;
	// How far the capsule may reach out from the camera. The stock element
	// returns what the island suggests; ours widens the leading side to at
	// least QD_ISLAND_LEADING_OUTSET in mode 1 and trims both sides in mode 2.
	// (Outsets are negative to the left; the sign is kept.)
	class_addMethod(subclass, sel_registerName("preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:"), imp_implementationWithBlock(^NSDirectionalEdgeInsets(id self, long long mode, NSDirectionalEdgeInsets suggested, NSDirectionalEdgeInsets maximum) {
		NSDirectionalEdgeInsets outsets = suggested;
		if (mode == 1) {
			CGFloat sign = suggested.leading < 0 ? -1 : 1;
			CGFloat wanted = MAX(fabs(suggested.leading), QD_ISLAND_LEADING_OUTSET);
			if (maximum.leading != 0)
				wanted = MIN(wanted, fabs(maximum.leading));
			outsets.leading = sign * wanted;
		} else if (mode == 2 && suggested.leading < 0) {
			outsets.leading = -MIN(fabs(suggested.leading), QD_ISLAND_ALONE_LEADING);
			// the trailing side is only an empty placeholder
			if (suggested.trailing < 0)
				outsets.trailing = -MIN(fabs(suggested.trailing), QD_ISLAND_ALONE_TRAILING);
		}
		QDDebugLog(@"outsets for mode %lld: suggested %@, maximum %@, returning %@", mode, NSStringFromDirectionalEdgeInsets(suggested), NSStringFromDirectionalEdgeInsets(maximum), NSStringFromDirectionalEdgeInsets(outsets));
		return outsets;
	}), "{NSDirectionalEdgeInsets=dddd}@:q{NSDirectionalEdgeInsets=dddd}{NSDirectionalEdgeInsets=dddd}");
	objc_registerClassPair(subclass);
	return subclass;
}

static UIColor *islandColor(BOOL success) {
	return success ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
}

// The island icon: the same SF Symbols as the pill (the eye with its warning
// badge, or a check mark), at the left end of a transparent picture so it
// clears the capsule's round end. iconHeight is the symbol's height, scaled
// to fit the picture's remaining width if need be.
static UIImage *islandCanvas(BOOL success, CGSize canvas, CGFloat margin, CGFloat iconHeight) {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightBold];
	UIImage *symbol = [UIImage systemImageNamed:success ? @"checkmark" : @"eye.trianglebadge.exclamationmark.fill" withConfiguration:config];
	symbol = [symbol imageWithTintColor:islandColor(success) renderingMode:UIImageRenderingModeAlwaysOriginal];
	CGFloat scale = MIN(iconHeight / symbol.size.height, (canvas.width - margin) / symbol.size.width);
	CGSize size = CGSizeMake(symbol.size.width * scale, symbol.size.height * scale);
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.opaque = NO;
	return [[[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[symbol drawInRect:CGRectMake(margin, (canvas.height - size.height) / 2, size.width, size.height)];
	}];
}

static void setIslandIcon(BOOL success) {
	[islandIconViews.firstObject setImage:islandCanvas(success, QD_ISLAND_LEADING_SIZE, QD_ISLAND_LEADING_MARGIN, QD_ISLAND_LEADING_ICON_HEIGHT)];
	[islandIconViews.lastObject setImage:islandCanvas(success, QD_ISLAND_MINIMAL_SIZE, 0, QD_ISLAND_MINIMAL_ICON_HEIGHT)];
}

// a view with a fixed size: the island sizes its compact views by the
// view's own layout size, so one without would collapse to nothing
static UIView *islandSizedView(UIView *view, CGSize size) {
	view.translatesAutoresizingMaskIntoConstraints = NO;
	[NSLayoutConstraint activateConstraints:@[
		[view.widthAnchor constraintEqualToConstant:size.width],
		[view.heightAnchor constraintEqualToConstant:size.height],
	]];
	return view;
}

void QDIslandRemove(void) {
	if (!islandAssertion)
		return;
	QDDebugLog(@"removing the Dynamic Island element");
	[islandAssertion invalidateWithReason:@"ScreenDistancePill is done"];
	islandAssertion = nil;
	islandIconViews = nil;
}

// The System Aperture controller of SpringBoard's main window scene, nil on an
// iPhone without a Dynamic Island. sawWindowScene says whether any scene that
// could have one exists yet, so nil can be told from "not set up yet".
static id islandController(BOOL *sawWindowScene) {
	// not every scene on the main screen has one (the System Aperture has its
	// own scenes), so take the first scene that does
	id controller = nil;
	BOOL saw = NO;
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		BOOL responds = [scene respondsToSelector:@selector(systemApertureController)];
		id candidate = responds ? [(UIWindowScene *)scene systemApertureController] : nil;
		QDDebugLog(@"scene %@: systemApertureController %@", NSStringFromClass([scene class]), responds ? (candidate ?: @"nil") : @"not supported");
		saw |= responds;
		if (candidate && !controller)
			controller = candidate;
	}
	if (sawWindowScene)
		*sawWindowScene = saw;
	return controller;
}

// Everything here was worked out on iOS 17. A later System Aperture may have
// changed these private methods, and calling one that is gone would crash
// SpringBoard, so check each one first and use the pill if any is missing.
static BOOL islandUsable(id controller) {
	if (!controller) {
		QDDebugLog(@"no Dynamic Island here");
		return NO;
	}
	if (@available(iOS 18.0, *)) {
		QDDebugLog(@"Dynamic Island mode is only checked on iOS 17, using the pill");
		return NO;
	}
	Class elementClass = NSClassFromString(@"SBActivityProvidedContentElement");
	Class contentClass = NSClassFromString(@"SBUISystemApertureContentProvider");
	Class imageClass = NSClassFromString(@"SBUISystemApertureCustomContentProvider");
	Class identificationClass = NSClassFromString(@"SBSAElementIdentification");
	if (![controller respondsToSelector:@selector(registerElement:)]
		|| ![identificationClass instancesRespondToSelector:@selector(initWithClientIdentifier:elementIdentifier:)]
		|| ![elementClass instancesRespondToSelector:@selector(initWithIdentifier:contentProvider:)]
		|| ![elementClass instancesRespondToSelector:@selector(setMinimumSupportedLayoutMode:)]
		|| ![elementClass instancesRespondToSelector:@selector(setMaximumSupportedLayoutMode:)]
		|| ![elementClass instancesRespondToSelector:@selector(setPreferredLayoutMode:)]
		|| ![contentClass instancesRespondToSelector:@selector(setLeadingContentViewProvider:)]
		|| ![contentClass instancesRespondToSelector:@selector(setTrailingContentViewProvider:)]
		|| ![contentClass instancesRespondToSelector:@selector(setMinimalContentViewProvider:)]
		|| ![imageClass instancesRespondToSelector:@selector(initWithView:)]) {
		QDDebugLog(@"the Dynamic Island's private methods are not what this expects, using the pill");
		return NO;
	}
	return YES;
}

// YES if the eye icon is now in the Dynamic Island
BOOL QDIslandShow(void) {
	QDIslandRemove();
	id controller = islandController(NULL);
	if (!islandUsable(controller))
		return NO;
	// an activity element (like a timer): the island only builds a view for
	// elements that have alert or activity behavior, a plain one crashes it
	Class elementClass = NSClassFromString(@"SBActivityProvidedContentElement");
	Class contentClass = NSClassFromString(@"SBUISystemApertureContentProvider");
	Class imageClass = NSClassFromString(@"SBUISystemApertureCustomContentProvider");
	// the element wants an identification object (client + element id), not a string
	Class identificationClass = NSClassFromString(@"SBSAElementIdentification");
	UIImageView *leadingPicture = [[UIImageView alloc] initWithImage:islandCanvas(NO, QD_ISLAND_LEADING_SIZE, QD_ISLAND_LEADING_MARGIN, QD_ISLAND_LEADING_ICON_HEIGHT)];
	leadingPicture.contentMode = UIViewContentModeLeft;
	islandSizedView(leadingPicture, QD_ISLAND_LEADING_SIZE);
	UIImageView *minimalView = [[UIImageView alloc] initWithImage:islandCanvas(NO, QD_ISLAND_MINIMAL_SIZE, 0, QD_ISLAND_MINIMAL_ICON_HEIGHT)];
	minimalView.contentMode = UIViewContentModeLeft;
	islandSizedView(minimalView, QD_ISLAND_MINIMAL_SIZE);
	id leading = [[imageClass alloc] initWithView:leadingPicture];
	id minimal = [[imageClass alloc] initWithView:minimalView];
	// nothing on the trailing side, but the compact layout wants one
	id trailing = [[imageClass alloc] initWithView:islandSizedView([UIView new], CGSizeMake(20, 20))];
	id content = [contentClass new];
	[content setLeadingContentViewProvider:leading];
	[content setTrailingContentViewProvider:trailing];
	[content setMinimalContentViewProvider:minimal];
	id identification = [[identificationClass alloc] initWithClientIdentifier:@"com.qn.screendistancepill" elementIdentifier:@"com.qn.screendistancepill.eye"];
	id element = identification ? [[islandElementClass(elementClass) alloc] initWithIdentifier:identification contentProvider:content] : nil;
	// the element starts out expanded (3), which is the huge island; keep it
	// between minimal (1) and compact (2), like a media player's. The minimum
	// has to be set too: left at 3 it is above the maximum and nothing shows.
	[element setMinimumSupportedLayoutMode:1];
	[element setMaximumSupportedLayoutMode:2];
	[element setPreferredLayoutMode:2];
	id assertion = element ? [controller registerElement:element] : nil;
	if (!assertion) {
		QDDebugLog(@"the Dynamic Island refused the element");
		return NO;
	}
	islandAssertion = assertion;
	islandIconViews = @[ leadingPicture, minimalView ];
	QDDebugLog(@"element in the Dynamic Island: %@", element);
	return YES;
}

void QDIslandShowSuccess(void) {
	setIslandIcon(YES);
}

// SpringBoard's scenes don't exist yet when the tweak loads, so ask a little
// later, and again until a scene that could have a Dynamic Island shows up.
static void publishIslandSupport(int attempt) {
	BOOL sawWindowScene = NO;
	id controller = islandController(&sawWindowScene);
	if (!controller && !sawWindowScene && attempt < 15) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			publishIslandSupport(attempt + 1);
		});
		return;
	}
	BOOL supported = islandUsable(controller);
	NSNumber *stored = [QDPrefs load][QD_KEY_ISLAND_SUPPORTED];
	if (![stored isKindOfClass:[NSNumber class]] || stored.boolValue != supported) {
		QDDebugLog(@"Dynamic Island support: %d, written to the preferences", supported);
		[QDPrefs setObject:@(supported) forKey:QD_KEY_ISLAND_SUPPORTED];
	}
}

void QDIslandPublishSupport(void) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		publishIslandSupport(0);
	});
}
