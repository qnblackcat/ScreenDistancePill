// Dynamic Island mode, see PillDynamicIsland.m.
#import <Foundation/Foundation.h>

// Puts the warning (an orange eye) in the Dynamic Island. NO if it can't be
// used here (no Dynamic Island, not iOS 17, a private method missing): the
// caller shows the pill instead.
BOOL QDIslandShow(void);
// Changes the icon to a green check mark; the element stays until removed.
void QDIslandShowSuccess(void);
// Takes the element out of the Dynamic Island; safe to call when it isn't there.
void QDIslandRemove(void);

// Works out, once SpringBoard has set up its scenes, whether this iPhone has a
// Dynamic Island the tweak can use, and writes the answer to the preferences
// (QD_KEY_ISLAND_SUPPORTED) for Settings, which can't see SpringBoard's
// scenes, to grey the switch out. Call once, from SpringBoard.
void QDIslandPublishSupport(void);
