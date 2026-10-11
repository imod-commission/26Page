ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 26Page

26Page_FILES = Tweak.x
26Page_CFLAGS = -fobjc-arc -Wno-unused-function
26Page_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk