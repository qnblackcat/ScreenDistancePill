#import <Foundation/Foundation.h>

// QDLog: always goes to the unified log with the "[ScreenDistancePill]" prefix;
// while Debug is on (Settings → ScreenDistancePill → Troubleshooting) it is also
// appended to this process's debug log file.
// QDDebugLog: only while Debug is on. A macro so the arguments are not even
// evaluated when Debug is off.
//
// Debug log files live in jbroot, one per process (eyereliefd.log,
// SpringBoard.log, Preferences.log), each capped at QDLogFileMaxBytes and
// rotated to <name>.1.

#define QDLogFileMaxBytes (128 * 1024)

void QDLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#define QDDebugLog(...) do { if (QDDebugEnabled()) QDLog(__VA_ARGS__); } while (0)

// read from the notify state SpringBoard publishes (QD_DEBUG_STATE), so it
// also works in eyereliefd's sandbox
BOOL QDDebugEnabled(void);

// All processes' logs merged by time, newest last, limited to the last
// maxBytes characters.
NSString *QDLogFileRead(NSUInteger maxBytes);
void QDLogFileClear(void);
