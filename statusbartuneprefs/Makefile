TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = statusbartuneprefs

statusbartuneprefs_FILES = SBTRootListController.m
statusbartuneprefs_FRAMEWORKS = UIKit
statusbartuneprefs_PRIVATE_FRAMEWORKS = Preferences
statusbartuneprefs_INSTALL_PATH = /Library/PreferenceBundles
statusbartuneprefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
