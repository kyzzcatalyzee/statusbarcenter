#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface SBTRootListController : PSListController
@end

@implementation SBTRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)resetValues {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.zilvyn.statusbartune"];
    [prefs setFloat:0 forKey:@"offsetY"];
    [prefs setFloat:0 forKey:@"paddingLeft"];
    [prefs setFloat:0 forKey:@"paddingRight"];
    [prefs synchronize];
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zilvyn.statusbartune/prefschanged"),
        NULL, NULL, YES);
    [self reloadSpecifiers];
}

@end
