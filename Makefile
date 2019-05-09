export ADDITIONAL_CFLAGS = -I$(THEOS_PROJECT_DIR)/../headers
# export USE_SUBSTRATE=0
include $(THEOS)/makefiles/common.mk

ARCHS = armv7 arm64 arm64e

TWEAK_NAME = PeekaBoo
PeekaBoo_CFLAGS = -fobjc-arc -I./headers -std=c++11 -stdlib=libc++
PeekaBoo_FILES = Tweak.xm
PeekaBoo_FRAMEWORKS = UIKit AudioToolbox CoreMedia
PeekaBoo_LIBRARIES = MobileGestalt
PeekaBoo_LDFLAGS += ./AppSupport.tbd ./IOKit.tbd -stdlib=libc++

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += settings
include $(THEOS_MAKE_PATH)/aggregate.mk
