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
// Posisi Y asli (sebelum offset) tiap view status bar
static NSMapTable<UIView *, NSNumber *> *baseOriginY;

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

// Kumpulkan view "item" status bar (jam, ikon pesawat, wifi, baterai, dst.)
static void collectItems(UIView *view, NSMutableArray<UIView *> *out) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha < 0.01 || CGRectIsEmpty(sub.bounds)) continue;

        NSString *name = NSStringFromClass([sub class]);
        // Lewati latar/pil aktivitas dan view besar yang bukan ikon
        if ([name rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound) continue;

        BOOL isBattery = [name rangeOfString:@"Battery" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (isBattery || sub.subviews.count == 0) {
            if (sub.bounds.size.width <= 120) [out addObject:sub];
        } else {
            collectItems(sub, out);
        }
    }
}

// Tinggi (posisi vertikal): geser origin.y view status bar lewat frame
static void applyVertical(UIView *foreground) {
    NSNumber *base = [baseOriginY objectForKey:foreground];
    if (!base) return;

    CGFloat target = base.doubleValue + (tweakEnabled ? offsetY : 0);
    CGRect frame = foreground.frame;
    if (fabs(frame.origin.y - target) < 0.01) return;

    frame.origin.y = target;
    bypassFrameHook = YES;
    foreground.frame = frame;
    bypassFrameHook = NO;
}

// Jarak ke tengah: jam (kiri) dan ikon (kanan) digeser mendekat atau menjauh dari tengah
static void applyHorizontal(UIView *foreground) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    collectItems(foreground, items);

    // Reset dulu supaya posisi asli bisa dibaca dengan benar
    for (UIView *item in items) {
        if (!CGAffineTransformIsIdentity(item.transform)) {
            item.transform = CGAffineTransformIdentity;
        }
    }

    CGFloat left = tweakEnabled ? paddingLeft : 0;
    CGFloat right = tweakEnabled ? paddingRight : 0;
    if (left == 0 && right == 0) return;

    CGFloat midX = CGRectGetMidX(foreground.bounds);
    for (UIView *item in items) {
        CGPoint center = [foreground convertPoint:CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds))
                                         fromView:item];
        if (center.x < midX) {
            // Sisi kiri (jam dan ikon di sebelahnya): geser ke kanan, ke arah tengah
            item.transform = CGAffineTransformMakeTranslation(left, 0);
        } else {
            // Sisi kanan (pesawat, wifi, baterai): geser ke kiri, ke arah tengah
            item.transform = CGAffineTransformMakeTranslation(-right, 0);
        }
    }
}

static void applyStatusBar(UIView *foreground) {
    if (!foreground.window) return;
    applyVertical(foreground);
    applyHorizontal(foreground);
}

static void applyAll(void) {
    for (UIView *view in [foregroundViews allObjects]) {
        applyStatusBar(view);
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
    [baseOriginY setObject:@(frame.origin.y) forKey:self];
    if (tweakEnabled) frame.origin.y += offsetY;
    %orig(frame);
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    if (![baseOriginY objectForKey:self]) {
        [baseOriginY setObject:@(self.frame.origin.y) forKey:self];
    }
    [foregroundViews addObject:self];
    applyStatusBar(self);

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

- (void)layoutSubviews {
    %orig;
    applyStatusBar(self);
}

%end

%ctor {
    NSString *processID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    isSpringBoard = [processID isEqualToString:@"com.apple.springboard"];

    foregroundViews = [NSHashTable weakObjectsHashTable];
    baseOriginY = [NSMapTable weakToStrongObjectsMapTable];
    loadPrefs();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        prefsChanged,
        kPrefsChanged,
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    // Status bar sering berubah isinya (ikon muncul/hilang) tanpa layout ulang, jadi segarkan berkala
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            if (tweakEnabled && (paddingLeft != 0 || paddingRight != 0)) applyAll();
        }];
    });

    %init;
}
