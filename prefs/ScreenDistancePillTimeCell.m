#import "ScreenDistancePillTimeCell.h"
#import <Preferences/PSSpecifier.h>

// in Preferences, not in Theos's header
@interface PSTableCell (QDPrivate)
- (void)setCellEnabled:(BOOL)enabled;
@end

@implementation QDTimeCell {
	UIDatePicker *_picker;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
	if (!self)
		return nil;
	_picker = [UIDatePicker new];
	_picker.datePickerMode = UIDatePickerModeTime;
	_picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
	_picker.minuteInterval = 5;
	// minutes since midnight are wall-clock times: keep the picker in GMT so
	// they map to it 1:1 whatever the device's time zone
	_picker.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	[_picker addTarget:self action:@selector(pickerChanged) forControlEvents:UIControlEventValueChanged];
	[_picker sizeToFit];
	self.accessoryView = _picker;
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	return self;
}

// PSTableCell shows the getter's value as detail text; here that's the raw
// minutes (1320, 420), and the picker already shows the time
- (void)setValue:(id)value {
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.detailTextLabel.text = nil;
	id value = [specifier performGetter];
	NSInteger minutes = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
	_picker.date = [NSDate dateWithTimeIntervalSince1970:minutes * 60];
	_picker.enabled = [[specifier propertyForKey:@"enabled"] ?: @YES boolValue];
}

- (void)setCellEnabled:(BOOL)enabled {
	[super setCellEnabled:enabled];
	_picker.enabled = enabled;
}

- (void)pickerChanged {
	NSInteger seconds = (NSInteger)_picker.date.timeIntervalSince1970 % (24 * 60 * 60);
	if (seconds < 0)
		seconds += 24 * 60 * 60;
	[self.specifier performSetterWithValue:@(seconds / 60)];
}

@end
