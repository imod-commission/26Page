#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL NeedTweak(void) {
    static BOOL need = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSOperatingSystemVersion v;
        v = [[NSProcessInfo processInfo] operatingSystemVersion];
        need = (v.majorVersion < 26);
    });
    return need;
}

static UIView *SafeView(id obj) {
    if (!obj) return nil;
    if (![obj isKindOfClass:[UIViewController class]]) return nil;
    return [(UIViewController *)obj view];
}

static BOOL IsOnHomeScreen(UIView *pageView) {
    if (!pageView) return NO;
    UIView *node = pageView;
    int i = 0;
    while (node && i < 20) {
        NSString *cls = NSStringFromClass(node.class);
        if ([cls containsString:@"HomeScreenWindow"]) return YES;
        if ([cls containsString:@"CoverSheet"]) return NO;
        if ([cls containsString:@"LockScreen"]) return NO;
        node = node.superview;
        i++;
    }
    return NO;
}

static BOOL IsBlurCls(NSString *c) {
    if (c.length == 0) return NO;
    if ([c isEqualToString:@"MTMaterialView"]) return YES;
    if ([c isEqualToString:@"_UIBackdropView"]) return YES;
    return NO;
}

static void CleanBlurNearPage(UIView *pv) {
    if (!pv) return;
    if (!IsOnHomeScreen(pv)) return;
    UIView *node = pv;
    int level = 0;
    while (node && level < 6) {
        UIView *parent = node.superview;
        if (parent) {
            NSString *pCls = NSStringFromClass(parent.class);
            if (![pCls containsString:@"HomeScreen"]) {
                for (UIView *sib in parent.subviews) {
                    if (sib == node) continue;
                    NSString *cls = NSStringFromClass(sib.class);
                    if (!IsBlurCls(cls)) continue;
                    if ([cls containsString:@"Switcher"]) continue;
                    if ([cls containsString:@"Dock"]) continue;
                    if ([cls containsString:@"Control"]) continue;
                    if ([cls containsString:@"Notif"]) continue;
                    sib.hidden = YES;
                    sib.alpha = 0.0f;
                }
            }
        }
        node = parent;
        level++;
    }
}

static UIView *FindHomeContainer(UIView *pageView) {
    if (!pageView) return nil;
    UIView *iconContent = nil;
    UIView *node = pageView;
    int i = 0;
    while (node && i < 10) {
        NSString *cls = NSStringFromClass(node.class);
        if ([cls isEqualToString:@"SBIconContentView"]) {
            iconContent = node;
            break;
        }
        node = node.superview;
        i++;
    }
    if (!iconContent) return nil;
    for (UIView *sib in iconContent.subviews) {
        NSString *cls = NSStringFromClass(sib.class);
        if ([cls isEqualToString:@"SBFolderContainerView"]) return sib;
    }
    return nil;
}

static UIViewController *FindInnerOverlayVC(UIViewController *vc) {
    if (!vc) return nil;
    Class todayCls = NSClassFromString(@"SBTodayViewController");
    Class libCls = NSClassFromString(@"SBHLibraryViewController");
    if (todayCls && [vc isKindOfClass:todayCls]) return vc;
    if (libCls && [vc isKindOfClass:libCls]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *r = FindInnerOverlayVC(child);
        if (r) return r;
    }
    return nil;
}

static double ReadBestProgress(id ctrl) {
    if (!ctrl) return -1;
    SEL s1 = NSSelectorFromString(@"layerPresentationProgress");
    if ([ctrl respondsToSelector:s1]) {
        IMP imp = [ctrl methodForSelector:s1];
        double (*fn)(id, SEL) = (void *)imp;
        return fn(ctrl, s1);
    }
    SEL s2 = NSSelectorFromString(@"presentationProgress");
    if ([ctrl respondsToSelector:s2]) {
        IMP imp = [ctrl methodForSelector:s2];
        double (*fn)(id, SEL) = (void *)imp;
        return fn(ctrl, s2);
    }
    return -1;
}

static void ApplyHomeTransform(id overlayCtrl, double p) {
    if (!overlayCtrl) return;
    Ivar iv = class_getInstanceVariable(object_getClass(overlayCtrl), "_overlayViewController");
    if (!iv) return;
    id overlayVC = object_getIvar(overlayCtrl, iv);
    if (![overlayVC isKindOfClass:[UIViewController class]]) return;
    UIViewController *inner = FindInnerOverlayVC((UIViewController *)overlayVC);
    if (!inner) return;
    UIView *pageView = inner.view;
    if (!pageView || !IsOnHomeScreen(pageView)) return;
    UIView *home = FindHomeContainer(pageView);
    if (!home) return;
    CGFloat w = home.bounds.size.width;
    if (w <= 0) return;
    BOOL isToday = [inner isKindOfClass:NSClassFromString(@"SBTodayViewController")];
    CGFloat tx = isToday ? (w * p) : (-w * p);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    home.transform = CGAffineTransformMakeTranslation(tx, 0);
    [CATransaction commit];
}

@interface _DPTarget : NSObject
@property (nonatomic, copy) void (^block)(CADisplayLink *);
- (void)tick:(CADisplayLink *)link;
@end
@implementation _DPTarget
- (void)tick:(CADisplayLink *)link { if (self.block) self.block(link); }
@end

static CADisplayLink *gLink = nil;
static _DPTarget *gTarget = nil;
static __weak id gOverlayCtrl = nil;

static void StartPolling(id ctrl) {
    if (!ctrl) return;
    gOverlayCtrl = ctrl;
    if (gLink) return;
    gTarget = [_DPTarget new];
    gTarget.block = ^(CADisplayLink *link) {
        id c = gOverlayCtrl;
        if (!c) { [link invalidate]; gLink = nil; gTarget = nil; return; }
        double p = ReadBestProgress(c);
        if (p >= 0) ApplyHomeTransform(c, p);
    };
    gLink = [CADisplayLink displayLinkWithTarget:gTarget selector:@selector(tick:)];
    [gLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

%hook SBTodayViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    if (!NeedTweak()) return;
    CleanBlurNearPage(SafeView(self));
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!NeedTweak()) return;
    CleanBlurNearPage(SafeView(self));
}

- (void)overlayController:(id)c
    didChangePresentationProgress:(double)from
        newPresentationProgress:(double)to
                  fromLeading:(BOOL)fromLeading {
    %orig;
    if (!NeedTweak()) return;
    ApplyHomeTransform(c, to);
    StartPolling(c);
    CleanBlurNearPage(SafeView(self));
}

%end

%hook SBHLibraryViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    if (!NeedTweak()) return;
    CleanBlurNearPage(SafeView(self));
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!NeedTweak()) return;
    CleanBlurNearPage(SafeView(self));
}

- (void)overlayController:(id)c
    didChangePresentationProgress:(double)from
        newPresentationProgress:(double)to
                  fromLeading:(BOOL)fromLeading {
    %orig;
    if (!NeedTweak()) return;
    ApplyHomeTransform(c, to);
    StartPolling(c);
    CleanBlurNearPage(SafeView(self));
}

%end

%hook SBHomeScreenOverlayController

- (void)setPresentationProgress:(double)p {
    %orig(p);
    if (!NeedTweak()) return;
    StartPolling(self);
}

- (void)animatePresentationProgress:(double)p
          withGestureLiftOffVelocity:(double)v
                  completionHandler:(id)c {
    %orig(p, v, c);
    if (!NeedTweak()) return;
    StartPolling(self);
}

%end