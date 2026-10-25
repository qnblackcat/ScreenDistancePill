#import <Preferences/PSListController.h>

// reads and writes our keys through QDPrefs and dims rows that depend on a
// switch; each page only names its plist
@interface QDListController : PSListController
@end

@interface QDRootListController : QDListController
@end

// 👁️ Warning Sensitivity: Distance, Remind After
@interface QDSensitivityListController : QDListController
@end

// 🎨 Appearance: Animation, Feedback
@interface QDAppearanceListController : QDListController
@end

// Exclude: Excluded Apps, Excluded Time
@interface QDExcludeListController : QDListController
@end
