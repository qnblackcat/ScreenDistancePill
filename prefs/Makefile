TARGET = iphone:clang:17.5:17.0
ARCHS = arm64 arm64e
SDP_VERSION := $(shell awk '/^Version:/ {print $$2}' ../control)

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ScreenDistancePillPrefs

ScreenDistancePillPrefs_FILES = ScreenDistancePillRootListController.m ScreenDistancePillTimeCell.m ../ScreenDistancePillPrefs.m ../ScreenDistancePillLog.m
ScreenDistancePillPrefs_INSTALL_PATH = /Library/PreferenceBundles
ScreenDistancePillPrefs_FRAMEWORKS = UIKit
ScreenDistancePillPrefs_PRIVATE_FRAMEWORKS = Preferences
ScreenDistancePillPrefs_CFLAGS = -fobjc-arc -DSDP_VERSION=\"$(SDP_VERSION)\"

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ScreenDistancePillPrefs.plist$(ECHO_END)
