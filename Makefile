TARGET = iphone:clang:17.5:17.0
INSTALL_TARGET_PROCESSES = SpringBoard eyereliefd Preferences
ARCHS = arm64 arm64e
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ScreenDistancePill

ScreenDistancePill_FILES = Daemon.x Pill.x PillDynamicIsland.m ScreenDistancePillPrefs.m ScreenDistancePillLog.m
ScreenDistancePill_FRAMEWORKS = UIKit
ScreenDistancePill_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
