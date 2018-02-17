SHARED_CFLAGS = -fobjc-arc
CFLAGS = -fobjc-arc
ADDITIONAL_OBJCFLAGS = -fobjc-arc
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PeekaBoo
PeekaBoo_FILES = PABRootListController.m PABAppSettingsController.m OrderedDictionary.m
PeekaBoo_INSTALL_PATH = /Library/PreferenceBundles
PeekaBoo_FRAMEWORKS = UIKit
PeekaBoo_LDFLAGS += ./Preferences.tbd ./SpringBoardServices.tbd
PeekaBoo_CFLAGS = -fobjc-arc -I./headers

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/PeekaBoo.plist$(ECHO_END)
