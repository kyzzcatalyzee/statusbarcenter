#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kPrefsDomain = @"com.zilvyn.statusbartune";
static CFStringRef const kPrefsChanged = CFSTR("com.zilvyn.statusbartune/prefschanged");
static NSString *const kDumpPath = @"/var/mobile/Library/Preferences/StatusBarTune-hierarchy.txt";

static BOOL tweakEnabled = YES;
static CGFloat offsetY = 0;       // positif = turun, negatif = naik (poin)
static CGFloat paddingLeft = 0;   // geser jam (sisi kiri) ke tengah (poin), negatif = ke tepi
static CGFloat paddingRight = 0;  // geser ikon (sisi kanan) ke tengah (poin), negatif = ke tepi

static BOOL isSpringBoard = NO;
static BOOL bypassFrameHook = NO;

// Referensi lemah ke view status bar supaya bisa di-refresh saat slider digeser
static NSHashTable *foregroundViews;
// Frame asli (sebelum diubah tweak) tiap view status bar
static NSMapTable<UIView *, NSValue *> *baseFrames;

@interface _UIStatusBarForegroundView : UIView
@end

static void loadPrefs(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsDomain];

    id enabledValue = [prefs objectForKey:@"enabled"];
    tweakEnabled = enabledValue ? [enabledValue boolValue] : YES;
    offsetY = [prefs floatForKey:@"offsetY"];
    paddingLeft = [prefs floatForKey:@"paddingLeft"];
    paddingRight = [prefs floatForKey:@"paddingRight"];
}

// Hitung frame baru dari frame asli:
// - sisi kiri (jam) dan sisi kanan (ikon) menempel ke tepi view ini, jadi mengecilkan
//   lebar view dari kiri/kanan akan menggeser keduanya ke arah tengah
// - origin.y digeser untuk mengatur tinggi
static CGRect adjustedFrame(CGRect base) {
    if (!tweakEnabled) return base;

    CGRect frame = base;
    frame.origin.x += paddingLeft;
    frame.size.width -= (paddingLeft + paddingRight);
    if (frame.size.width < 80) frame.size.width = 80; // jaga-jaga supaya tidak runtuh
    frame.origin.y += offsetY;
    return frame;
}

static void applyFrame(UIView *foreground) {
    NSValue *base = [baseFrames objectForKey:foreground];
    if (!base) return;

    CGRect target = adjustedFrame(base.CGRectValue);
    if (CGRectEqualToRect(foreground.frame, target)) return;

    bypassFrameHook = YES;
    foreground.frame = target;
    bypassFrameHook = NO;
}

static void applyAll(void) {
    for (UIView *view in [foregroundViews allObjects]) {
        applyFrame(view);
    }
}

// Tulis struktur view status bar sekali (hanya di SpringBoard, untuk diagnosa)
static void dumpHierarchy(UIView *view, int depth, NSMutableString *out) {
    NSString *indent = [@"" stringByPaddingToLength:(NSUInteger)depth * 2 withString:@" " startingAtIndex:0];
    [out appendFormat:@"%@%@ frame=%@ hidden=%d alpha=%.2f\n",
        indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), view.hidden, view.alpha];
    for (UIView *sub in view.subviews) {
        dumpHierarchy(sub, depth + 1, out);
    }
}

static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        loadPrefs();
        applyAll();
    });
}

%hook _UIStatusBarForegroundView

- (void)setFrame:(CGRect)frame {
    if (bypassFrameHook) {
        %orig(frame);
        return;
    }
    [baseFrames setObject:[NSValue valueWithCGRect:frame] forKey:self];
    %orig(adjustedFrame(frame));
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    if (![baseFrames objectForKey:self]) {
        [baseFrames setObject:[NSValue valueWithCGRect:self.frame] forKey:self];
    }
    [foregroundViews addObject:self];
    applyFrame(self);

    if (isSpringBoard) {
        static dispatch_once_t dumpOnce;
        dispatch_once(&dumpOnce, ^{
            __weak UIView *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIView *strongSelf = weakSelf;
                if (!strongSelf) return;
                NSMutableString *text = [NSMutableString string];
                dumpHierarchy(strongSelf, 0, text);
                [text writeToFile:kDumpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            });
        });
    }
}

%end

%ctor {
    NSString *processID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    isSpringBoard = [processID isEqualToString:@"com.apple.springboard"];

    foregroundViews = [NSHashTable weakObjectsHashTable];
    baseFrames = [NSMapTable weakToStrongObjectsMapTable];
    loadPrefs();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        prefsChanged,
        kPrefsChanged,
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    %init;
}
