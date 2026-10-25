// Runs inside SpringBoard: draws the pill that replaces the "iPhone is Too
// Close" shield. eyereliefd decides when it shows and hides (Daemon.x);
// SpringBoard takes it down by itself only on lock or timeout, and says so.
//
// Before showing it, SpringBoard applies the rules eyereliefd can't: Excluded
// Apps and Excluded Time. It also publishes the settings eyereliefd needs as
// notify states.
//
// The pill sits under the Dynamic Island on a system material, never takes
// touches and uses EyeReliefUI's localized title. At a safe distance the icon
// turns into a green check mark before the pill goes away. The Bouncing Icon /
// Orange Glow toggles add a shared beat every few seconds. Edge Glow (off by
// default) fades in an orange glow along the screen edges if the phone stays
// too close, pulsing on the same beat.

#import <UIKit/UIKit.h>
#import <notify.h>
#import "ScreenDistancePillPrefs.h"
#import "ScreenDistancePillLog.h"

// safety net in case eyereliefd goes away without hiding it
#define QD_PILL_TIMEOUT 200

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@end

@interface SpringBoard : UIApplication
- (SBApplication *)_accessibilityFrontMostApplication;
@end

@interface QDPillWindow : UIWindow
@end

@implementation QDPillWindow
// the pill is only a reminder; touches always go to whatever is underneath
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	return nil;
}
@end

// one beat of the pill while it is up: the icon bounces and the glow flares
// together, so both run off the same timer and can never drift apart
#define QD_BEAT_INTERVAL 3.2
#define QD_BEAT_DURATION 1.4
// the bounce effect's own speed, slowed to match the beat
#define QD_BOUNCE_SPEED 0.7
// glow shadow opacity between beats and at the peak of one
#define QD_GLOW_REST 0.2
#define QD_GLOW_PEAK 0.5
// the tint's layer opacity between beats; a beat takes it to 1
#define QD_TINT_REST 0.7
// plain (not glowing) shadow
#define QD_SHADOW_OPACITY 0.18
#define QD_SHADOW_RADIUS 14

static CGFloat hairlineWidth(void) {
	return 1.0 / [UIScreen mainScreen].scale;
}

// pins view to its container, inset by the given amounts
static NSArray<NSLayoutConstraint *> *pinConstraints(UIView *view, UIView *container, UIEdgeInsets insets) {
	return @[
		[view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
		[view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
		[view.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
		[view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
	];
}

@interface QDPillView : UIView
- (void)showWarning;
- (void)showSuccess;
// Bouncing Icon / Orange Glow settings; both stop by themselves on showSuccess.
// glowStrength scales the glow and tint, 1 is the default look.
- (void)startAttentionWithBounce:(BOOL)bounce glow:(BOOL)glow glowStrength:(CGFloat)glowStrength;
- (void)stopAttention;
// called on every beat, so other views can pulse in time with the pill
@property (nonatomic, copy) void (^beatHandler)(void);
@end

@implementation QDPillView {
	UIVisualEffectView *_material;
	// colored wash over the material while glowing
	UIView *_tint;
	UIView *_iconCircle;
	UIImageView *_icon;
	NSTimer *_beatTimer;
	BOOL _bounce;
	// glow and tint color while glowing, nil for the plain look
	UIColor *_glowColor;
	CGFloat _glowStrength;
}

static UIImage *pillSymbol(NSString *name, NSString *fallback) {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
	return [UIImage systemImageNamed:name withConfiguration:config] ?: [UIImage systemImageNamed:fallback withConfiguration:config];
}

static NSString *pillTitle(void) {
	NSBundle *bundle = [NSBundle bundleWithPath:@"/Applications/EyeReliefUI.app"];
	NSString *fallback = @"iPhone May Be Too Close";
	return [bundle localizedStringForKey:@"TOO_CLOSE_TITLE_STRING_IPHONE" value:fallback table:@"Localizable"] ?: fallback;
}

- (instancetype)init {
	self = [super initWithFrame:CGRectZero];
	if (!self)
		return nil;
	self.translatesAutoresizingMaskIntoConstraints = NO;
	_glowStrength = 1;

	// soft shadow on the outer view, the material itself is clipped
	self.layer.shadowColor = [UIColor blackColor].CGColor;
	self.layer.shadowOpacity = QD_SHADOW_OPACITY;
	self.layer.shadowRadius = QD_SHADOW_RADIUS;
	self.layer.shadowOffset = CGSizeMake(0, 4);

	_material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
	_material.translatesAutoresizingMaskIntoConstraints = NO;
	_material.clipsToBounds = YES;
	_material.layer.cornerCurve = kCACornerCurveContinuous;
	_material.layer.borderWidth = hairlineWidth();
	[self addSubview:_material];

	_tint = [UIView new];
	_tint.translatesAutoresizingMaskIntoConstraints = NO;
	_tint.hidden = YES;
	[_material.contentView addSubview:_tint];

	_iconCircle = [UIView new];
	_iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
	_iconCircle.layer.cornerRadius = 14;
	_icon = [UIImageView new];
	_icon.translatesAutoresizingMaskIntoConstraints = NO;
	_icon.contentMode = UIViewContentModeCenter;
	[_iconCircle addSubview:_icon];

	UILabel *label = [UILabel new];
	label.text = pillTitle();
	label.textColor = [UIColor labelColor];
	label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	label.adjustsFontSizeToFitWidth = YES;
	label.minimumScaleFactor = 0.8;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _iconCircle, label ]];
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 10;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[_material.contentView addSubview:stack];

	UIView *content = _material.contentView;
	[NSLayoutConstraint activateConstraints:pinConstraints(_material, self, UIEdgeInsetsZero)];
	[NSLayoutConstraint activateConstraints:pinConstraints(_tint, content, UIEdgeInsetsZero)];
	[NSLayoutConstraint activateConstraints:pinConstraints(stack, content, UIEdgeInsetsMake(8, 8, 8, 18))];
	[NSLayoutConstraint activateConstraints:@[
		[_iconCircle.widthAnchor constraintEqualToConstant:28],
		[_iconCircle.heightAnchor constraintEqualToConstant:28],
		[_icon.centerXAnchor constraintEqualToAnchor:_iconCircle.centerXAnchor],
		[_icon.centerYAnchor constraintEqualToAnchor:_iconCircle.centerYAnchor],
	]];

	[self updateBorderColor];
	__weak QDPillView *weakSelf = self;
	[self registerForTraitChanges:@[ [UITraitUserInterfaceStyle class] ] withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
		[weakSelf updateBorderColor];
	}];

	[self showWarning];
	return self;
}

// CGColors don't follow dark mode by themselves
- (void)updateBorderColor {
	_material.layer.borderColor = [[UIColor separatorColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
	self.layer.shadowColor = [_glowColor ?: [UIColor blackColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat radius = self.bounds.size.height / 2;
	_material.layer.cornerRadius = radius;
	self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
}

- (void)setIcon:(UIImage *)image color:(UIColor *)color {
	_icon.image = image;
	_icon.tintColor = color;
	_iconCircle.backgroundColor = [color colorWithAlphaComponent:0.18];
}

- (void)showWarning {
	[self setIcon:pillSymbol(@"eye.trianglebadge.exclamationmark.fill", @"eye.fill") color:[UIColor systemOrangeColor]];
}

- (void)showSuccess {
	BOOL wasGlowing = _glowColor != nil;
	[self stopAttention];
	// the glow and tint stay on as a steady green until the pill fades out
	if (wasGlowing) {
		[self setGlowColor:[UIColor systemGreenColor] opacity:0.35 radius:QD_SHADOW_RADIUS];
		_tint.alpha = 1;
	}
	[UIView transitionWithView:_iconCircle duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
		[self setIcon:pillSymbol(@"checkmark", @"checkmark.circle.fill") color:[UIColor systemGreenColor]];
	} completion:nil];
}

// The material is near white in light mode and near black in dark mode, so
// the same alpha reads much weaker on dark; dark mode gets a stronger wash.
// A dynamic color, so the view follows mode changes by itself.
static UIColor *tintWash(UIColor *color, CGFloat strength) {
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
		CGFloat alpha = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.40 : 0.30;
		return [[color resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:MIN(alpha * strength, 1)];
	}];
}

// a glow opacity scaled by the Orange Glow strength
- (float)glowOpacity:(float)opacity {
	return MIN(opacity * _glowStrength, 1);
}

// opacity is scaled by the glow strength, except for the plain black shadow
- (void)setGlowColor:(UIColor *)color opacity:(float)opacity radius:(CGFloat)radius {
	_glowColor = color;
	// the hairline is only for the plain pill; glow and tint already outline a colored one
	_material.layer.borderWidth = color ? 0 : hairlineWidth();
	self.layer.shadowOpacity = color ? [self glowOpacity:opacity] : opacity;
	self.layer.shadowRadius = radius;
	_tint.hidden = color == nil;
	_tint.backgroundColor = color ? tintWash(color, _glowStrength) : nil;
	_tint.alpha = QD_TINT_REST;
	[self updateBorderColor];
}

- (void)startAttentionWithBounce:(BOOL)bounce glow:(BOOL)glow glowStrength:(CGFloat)glowStrength {
	[self stopAttention];
	_glowStrength = glowStrength;
	// the timer runs even with both off: Edge Glow follows the same beat
	_bounce = bounce;
	// orange glow and tint, resting between beats
	if (glow)
		[self setGlowColor:[UIColor systemOrangeColor] opacity:QD_GLOW_REST radius:10];
	__weak QDPillView *weakSelf = self;
	_beatTimer = [NSTimer scheduledTimerWithTimeInterval:QD_BEAT_INTERVAL repeats:YES block:^(NSTimer *timer) {
		[weakSelf beat];
	}];
	// first beat right after the pop-in instead of a full interval later
	_beatTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
}

// rest → peak → rest, peaking early to line up with the top of the bounce
static CAKeyframeAnimation *beatAnimation(NSString *keyPath, id rest, id peak) {
	CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
	animation.values = @[ rest, peak, rest ];
	animation.keyTimes = @[ @0, @0.3, @1 ];
	animation.timingFunctions = @[
		[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
		[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
	];
	animation.duration = QD_BEAT_DURATION;
	return animation;
}

- (void)beat {
	if (self.beatHandler)
		self.beatHandler();
	if (_bounce)
		[_icon addSymbolEffect:[NSSymbolBounceEffect bounceUpEffect] options:[NSSymbolEffectOptions optionsWithSpeed:QD_BOUNCE_SPEED]];
	if (!_glowColor)
		return;
	CAAnimationGroup *glow = [CAAnimationGroup animation];
	glow.animations = @[
		beatAnimation(@"shadowOpacity", @([self glowOpacity:QD_GLOW_REST]), @([self glowOpacity:QD_GLOW_PEAK])),
		beatAnimation(@"shadowRadius", @10, @18),
	];
	glow.duration = QD_BEAT_DURATION;
	[self.layer addAnimation:glow forKey:@"qdBeat"];
	[_tint.layer addAnimation:beatAnimation(@"opacity", @(QD_TINT_REST), @1) forKey:@"qdBeat"];
}

- (void)stopAttention {
	[_beatTimer invalidate];
	_beatTimer = nil;
	_bounce = NO;
	[_icon removeAllSymbolEffects];
	[self.layer removeAnimationForKey:@"qdBeat"];
	[_tint.layer removeAnimationForKey:@"qdBeat"];
	[self setGlowColor:nil opacity:QD_SHADOW_OPACITY radius:QD_SHADOW_RADIUS];
}

@end

// Edge Glow: an orange glow along the screen edges that fades in when the
// phone stays too close for a while. Four gradients from each edge inwards;
// they add up in the corners, which the rounded display then clips.
@interface QDVignetteView : UIView
- (void)fadeIn;
- (void)fadeOutWithDuration:(NSTimeInterval)duration;
- (void)beat;
@end

// how far the glow reaches in from each edge
#define QD_VIGNETTE_DEPTH 70
#define QD_VIGNETTE_ALPHA 0.45

@implementation QDVignetteView {
	// the view's alpha fades it in and out, this layer's opacity beats
	CALayer *_glow;
	NSArray<CAGradientLayer *> *_edges;
	BOOL _active;
}

- (instancetype)init {
	self = [super initWithFrame:CGRectZero];
	if (!self)
		return nil;
	self.translatesAutoresizingMaskIntoConstraints = NO;
	self.userInteractionEnabled = NO;
	self.alpha = 0;
	_glow = [CALayer layer];
	_glow.opacity = QD_TINT_REST;
	[self.layer addSublayer:_glow];
	NSMutableArray *edges = [NSMutableArray array];
	// top, bottom, left, right: each starts at its edge and fades inwards
	NSArray<NSValue *> *starts = @[ @(CGPointMake(0.5, 0)), @(CGPointMake(0.5, 1)), @(CGPointMake(0, 0.5)), @(CGPointMake(1, 0.5)) ];
	NSArray<NSValue *> *ends = @[ @(CGPointMake(0.5, 1)), @(CGPointMake(0.5, 0)), @(CGPointMake(1, 0.5)), @(CGPointMake(0, 0.5)) ];
	for (NSUInteger i = 0; i < 4; i++) {
		CAGradientLayer *edge = [CAGradientLayer layer];
		edge.startPoint = starts[i].CGPointValue;
		edge.endPoint = ends[i].CGPointValue;
		[_glow addSublayer:edge];
		[edges addObject:edge];
	}
	_edges = edges;
	[self updateColors];
	__weak QDVignetteView *weakSelf = self;
	[self registerForTraitChanges:@[ [UITraitUserInterfaceStyle class] ] withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
		[weakSelf updateColors];
	}];
	return self;
}

- (void)updateColors {
	UIColor *orange = [[UIColor systemOrangeColor] resolvedColorWithTraitCollection:self.traitCollection];
	NSArray *colors = @[ (id)[orange colorWithAlphaComponent:QD_VIGNETTE_ALPHA].CGColor, (id)[orange colorWithAlphaComponent:0].CGColor ];
	for (CAGradientLayer *edge in _edges)
		edge.colors = colors;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGSize size = self.bounds.size;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_glow.frame = self.bounds;
	_edges[0].frame = CGRectMake(0, 0, size.width, QD_VIGNETTE_DEPTH);
	_edges[1].frame = CGRectMake(0, size.height - QD_VIGNETTE_DEPTH, size.width, QD_VIGNETTE_DEPTH);
	_edges[2].frame = CGRectMake(0, 0, QD_VIGNETTE_DEPTH, size.height);
	_edges[3].frame = CGRectMake(size.width - QD_VIGNETTE_DEPTH, 0, QD_VIGNETTE_DEPTH, size.height);
	[CATransaction commit];
}

- (void)fadeIn {
	_active = YES;
	// slow, so it creeps in rather than flashes
	[UIView animateWithDuration:1.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
		self.alpha = 1;
	} completion:nil];
}

- (void)fadeOutWithDuration:(NSTimeInterval)duration {
	if (!_active)
		return;
	_active = NO;
	[UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
		self.alpha = 0;
	} completion:^(BOOL finished) {
		if (finished)
			[self->_glow removeAnimationForKey:@"qdBeat"];
	}];
}

- (void)beat {
	if (_active)
		[_glow addAnimation:beatAnimation(@"opacity", @(QD_TINT_REST), @1) forKey:@"qdBeat"];
}

@end

static QDPillWindow *pillWindow;
static QDPillView *pillView;
static QDVignetteView *vignetteView;
static BOOL pillShown;
static NSUInteger pillGeneration;
// for the log: how long the pill stayed up
static NSDate *pillShownAt;

static UIWindowScene *mainWindowScene(void) {
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)scene).screen == [UIScreen mainScreen])
			return (UIWindowScene *)scene;
	}
	return nil;
}

static BOOL ensurePillWindow(void) {
	if (pillWindow)
		return YES;
	UIWindowScene *scene = mainWindowScene();
	if (!scene) {
		QDLog(@"no window scene for the pill");
		return NO;
	}
	pillWindow = [[QDPillWindow alloc] initWithWindowScene:scene];
	pillWindow.windowLevel = UIWindowLevelStatusBar + 100;
	pillWindow.backgroundColor = [UIColor clearColor];
	pillWindow.userInteractionEnabled = NO;
	UIViewController *root = [UIViewController new];
	root.view.backgroundColor = [UIColor clearColor];
	root.view.userInteractionEnabled = NO;
	pillWindow.rootViewController = root;

	// under the pill, so the glow never washes over it
	vignetteView = [QDVignetteView new];
	[root.view addSubview:vignetteView];
	[NSLayoutConstraint activateConstraints:@[
		[vignetteView.leadingAnchor constraintEqualToAnchor:root.view.leadingAnchor],
		[vignetteView.trailingAnchor constraintEqualToAnchor:root.view.trailingAnchor],
		[vignetteView.topAnchor constraintEqualToAnchor:root.view.topAnchor],
		[vignetteView.bottomAnchor constraintEqualToAnchor:root.view.bottomAnchor],
	]];

	pillView = [QDPillView new];
	pillView.beatHandler = ^{
		[vignetteView beat];
	};
	[root.view addSubview:pillView];
	// the status bar is as tall as the Dynamic Island area, so this puts the
	// pill just below the island
	CGFloat top = scene.statusBarManager.statusBarFrame.size.height + 6;
	[NSLayoutConstraint activateConstraints:@[
		[pillView.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
		[pillView.topAnchor constraintEqualToAnchor:root.view.topAnchor constant:top],
		[pillView.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.view.leadingAnchor constant:20],
	]];
	return YES;
}

// same values and styles as FlicksForAll's haptic strength picker
static void playShowHaptic(NSDictionary *prefs) {
	if (![prefs[@"pillHaptic"] ?: @NO boolValue])
		return;
	NSString *strength = prefs[@"pillHapticStrength"] ?: @"light";
	NSDictionary<NSString *, NSNumber *> *styles = @{
		@"soft": @(UIImpactFeedbackStyleSoft),
		@"light": @(UIImpactFeedbackStyleLight),
		@"medium": @(UIImpactFeedbackStyleMedium),
		@"heavy": @(UIImpactFeedbackStyleHeavy),
	};
	NSNumber *style = styles[strength];
	if (style)
		[[[UIImpactFeedbackGenerator alloc] initWithStyle:style.integerValue] impactOccurred];
	else
		[[UISelectionFeedbackGenerator new] selectionChanged];
}

// a Settings slider, clamped to its range
static double sliderValue(NSDictionary *prefs, NSString *key, double fallback, double min, double max) {
	id value = prefs[key];
	double number = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
	return MIN(MAX(number, min), max);
}

// "Fade In/Out" slider: the pop-in spring and the fade-out both take this long
static NSTimeInterval pillFadeDuration(NSDictionary *prefs) {
	return sliderValue(prefs, @"pillShowDuration", 0.6, 0.2, 1.2);
}

static void fadeOutPill(NSUInteger generation, NSTimeInterval duration) {
	// ease-out: most of the fade happens early, like the spring on the way in
	[UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
		pillView.alpha = 0;
		pillView.transform = CGAffineTransformMakeScale(0.85, 0.85);
	} completion:^(BOOL finished) {
		// a new show may have started meanwhile
		if (generation == pillGeneration && !pillShown) {
			[pillView stopAttention];
			pillWindow.hidden = YES;
		}
	}];
}

// distanceFine: eyereliefd saw a safe distance, so show the check mark first
static void hidePill(BOOL distanceFine, NSString *reason) {
	if (!pillShown)
		return;
	pillShown = NO;
	NSUInteger generation = ++pillGeneration;
	NSTimeInterval shownFor = -[pillShownAt timeIntervalSinceNow];
	QDDebugLog(@"hiding pill after %.1f s: %@", shownFor, reason);
	NSDictionary *prefs = [QDPrefs load];
	NSTimeInterval fade = pillFadeDuration(prefs);
	// goes right away, even while the check mark is still showing
	[vignetteView fadeOutWithDuration:fade];
	if (!distanceFine) {
		notify_post(QD_PILL_DISMISSED);
		fadeOutPill(generation, fade);
		return;
	}
	[pillView showSuccess];
	NSTimeInterval hold = sliderValue(prefs, @"pillCheckHold", 1.2, 0.2, 2.2);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation == pillGeneration)
			fadeOutPill(generation, fade);
	});
}

static void showPill(BOOL test) {
	if (pillShown || !ensurePillWindow())
		return;
	pillShown = YES;
	pillShownAt = [NSDate date];
	NSUInteger generation = ++pillGeneration;
	QDDebugLog(@"showing pill%@", test ? @" (test)" : @"");

	[pillView showWarning];
	NSDictionary *prefs = [QDPrefs load];
	// Glow Strength slider, in percent
	CGFloat glowStrength = sliderValue(prefs, @"pillGlowStrength", 100, 50, 150) / 100;
	[pillView startAttentionWithBounce:[prefs[@"pillBounce"] ?: @YES boolValue] glow:[prefs[@"pillGlow"] ?: @YES boolValue] glowStrength:glowStrength];
	pillWindow.hidden = NO;
	[pillWindow layoutIfNeeded];
	pillView.alpha = 0;
	pillView.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.6, 0.6), CGAffineTransformMakeTranslation(0, -20));
	[UIView animateWithDuration:pillFadeDuration(prefs) delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
		pillView.alpha = 1;
		pillView.transform = CGAffineTransformIdentity;
	} completion:nil];
	playShowHaptic(prefs);

	if ([prefs[@"pillEdgeGlow"] ?: @NO boolValue]) {
		NSTimeInterval delay = sliderValue(prefs, @"pillEdgeGlowDelay", 15, 5, 25);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (generation != pillGeneration || !pillShown)
				return;
			QDDebugLog(@"still too close after %.0f s, showing the edge glow", delay);
			[vignetteView fadeIn];
		});
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, QD_PILL_TIMEOUT * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (generation == pillGeneration)
			hidePill(NO, @"timed out");
	});
}

// minutes since midnight
static NSInteger minutesSetting(NSDictionary *prefs, NSString *key, NSInteger fallback) {
	id value = prefs[key];
	NSInteger minutes = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
	return minutes >= 0 && minutes < 24 * 60 ? minutes : fallback;
}

// why a reminder should not show right now, nil if it should
static NSString *suppressionReason(void) {
	NSDictionary *prefs = [QDPrefs load];

	NSString *frontmost = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication].bundleIdentifier;
	NSArray *excluded = prefs[@"excludedApps"];
	if (frontmost && [excluded isKindOfClass:[NSArray class]] && [excluded containsObject:frontmost])
		return [NSString stringWithFormat:@"%@ is excluded", frontmost];

	if ([prefs[@"pauseEnabled"] ?: @NO boolValue]) {
		NSInteger start = minutesSetting(prefs, @"pauseStart", QD_DEFAULT_PAUSE_START);
		NSInteger end = minutesSetting(prefs, @"pauseEnd", QD_DEFAULT_PAUSE_END);
		NSDateComponents *now = [[NSCalendar currentCalendar] components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
		NSInteger minutes = now.hour * 60 + now.minute;
		// a window like 22:00 → 07:00 runs over midnight
		BOOL paused = start < end ? (minutes >= start && minutes < end) : start > end && (minutes >= start || minutes < end);
		if (paused)
			return [NSString stringWithFormat:@"excluded time %02ld:%02ld → %02ld:%02ld", (long)start / 60, (long)start % 60, (long)end / 60, (long)end % 60];
	}
	return nil;
}

static void handlePillRequest(QDPillRequest request) {
	if (!(request & QDPillRequestIgnoreRules)) {
		NSString *reason = suppressionReason();
		if (reason) {
			QDDebugLog(@"not showing the pill: %@", reason);
			notify_post(QD_PILL_SUPPRESSED);
			return;
		}
	}
	showPill((request & QDPillRequestTest) != 0);
}

// notifyd drops a name's state once nobody is registered for it, so the tokens
// stay open for SpringBoard's lifetime (a later eyereliefd would read 0).
static void publishState(const char *name, uint64_t value) {
	static NSMutableDictionary<NSString *, NSNumber *> *tokens;
	if (!tokens)
		tokens = [NSMutableDictionary dictionary];
	NSString *key = @(name);
	NSNumber *token = tokens[key];
	if (!token) {
		int newToken = NOTIFY_TOKEN_INVALID;
		if (notify_register_check(name, &newToken) != NOTIFY_STATUS_OK)
			return;
		token = @(newToken);
		tokens[key] = token;
	}
	notify_set_state(token.intValue, value);
}

// eyereliefd reads its settings from here: its sandbox may not reach the plist
static void publishSettings(void) {
	NSDictionary *prefs = [QDPrefs load];
	BOOL enabled = [prefs[@"enabled"] ?: @YES boolValue];
	BOOL debug = [prefs[@"debug"] ?: @NO boolValue];
	// the slider stores a double that may not land exactly on the whole number
	NSInteger distanceCm = lround([prefs[@"distanceCm"] ?: @(QD_DEFAULT_DISTANCE_CM) doubleValue]);
	NSInteger sensitivity = [prefs[@"sensitivity"] ?: @(QD_DEFAULT_SENSITIVITY) integerValue];
	publishState(QD_ENABLED_STATE, enabled ? QDEnabledStateOn : QDEnabledStateOff);
	publishState(QD_DEBUG_STATE, debug);
	publishState(QD_THRESHOLD_STATE, (uint64_t)MAX(distanceCm, 0) * 10);
	publishState(QD_SENSITIVITY_STATE, (uint64_t)MAX(sensitivity, 0));
	QDDebugLog(@"%s, debug %s, threshold %ld cm, sensitivity %ld samples",
		enabled ? "enabled" : "disabled", debug ? "on" : "off", (long)distanceCm, (long)sensitivity);
}

%ctor {
	if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
		return;

	publishSettings();

	int token;
	notify_register_dispatch(QD_PREFS_CHANGED, &token, dispatch_get_main_queue(), ^(int t) {
		publishSettings();
	});
	notify_register_dispatch(QD_PILL_SHOW, &token, dispatch_get_main_queue(), ^(int t) {
		uint64_t request = 0;
		notify_get_state(t, &request);
		handlePillRequest((QDPillRequest)request);
	});
	notify_register_dispatch(QD_PILL_HIDE, &token, dispatch_get_main_queue(), ^(int t) {
		hidePill(YES, @"eyereliefd says the distance is fine");
	});
	notify_register_dispatch(QD_PILL_CANCEL, &token, dispatch_get_main_queue(), ^(int t) {
		hidePill(NO, @"eyereliefd stopped watching");
	});
	// distance sampling stops on the lock screen, so the pill would never clear
	notify_register_dispatch("com.apple.springboard.lockcomplete", &token, dispatch_get_main_queue(), ^(int t) {
		hidePill(NO, @"device locked");
	});
}
