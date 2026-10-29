#import <Foundation/Foundation.h>

// QDDebugLog is the only way to log, and it does nothing unless Debug is on
// (Settings → ScreenDistancePill → Troubleshooting). A macro, so the arguments
// are not even evaluated when Debug is off. While on, each line goes to the
// unified log with the "[ScreenDistancePill]" prefix and is appended to this
// process's debug log file.
//
// Debug log files live in jbroot, one per process (eyereliefd.log,
// SpringBoard.log, Preferences.log), each capped at QDLogFileMaxBytes and
// rotated to <name>.1.

#define QDLogFileMaxBytes (128 * 1024)

#define QDDebugLog(...) do { if (QDDebugEnabled()) QDLogWrite(__VA_ARGS__); } while (0)

// what QDDebugLog calls once Debug is known to be on; don't call it directly
void QDLogWrite(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// read from the notify state SpringBoard publishes (QD_DEBUG_STATE), so it
// also works in eyereliefd's sandbox
BOOL QDDebugEnabled(void);

// All processes' logs merged by time, newest last, limited to the last
// maxBytes characters.
NSString *QDLogFileRead(NSUInteger maxBytes);
void QDLogFileClear(void);
