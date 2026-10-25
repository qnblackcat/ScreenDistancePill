#import <Preferences/PSTableCell.h>

// A row with a compact time picker on the right (cellClass = QDTimeCell in
// Root.plist). Reads and writes minutes since midnight through the
// specifier's getter and setter.
@interface QDTimeCell : PSTableCell
@end
