#import "MBXViewController.h"

#import <mbgl/ios/MGLMapView.h>

#import <mbgl/platform/darwin/settings_nsuserdefaults.hpp>

#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>
#import "MBXAnnotation.h"

static UIColor *const kTintColor = [UIColor colorWithRed:0.120 green:0.550 blue:0.670 alpha:1.000];

static NSArray *const kStyleNames = @[
    @"Bright",
    @"Basic",
    @"Outdoors",
    @"Satellite",
    @"Hybrid",
];

static NSString *const kStyleVersion = @"v7";

@interface MBXViewController () <UIActionSheetDelegate>

@property (nonatomic) MGLMapView *mapView;

@end

@implementation MBXViewController

mbgl::Settings_NSUserDefaults *settings = nullptr;

#pragma mark - Setup

- (id)init
{
    self = [super init];

    if (self)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveState:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(restoreState:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSString *accessToken = [[NSProcessInfo processInfo] environment][@"MAPBOX_ACCESS_TOKEN"];
    if (accessToken) {
        // Store to preferences so that we can launch the app later on without having to specify
        // token.
        [[NSUserDefaults standardUserDefaults] setObject:accessToken forKey:@"access_token"];
    } else {
        // Try to retrieve from preferences, maybe we've stored them there previously and can reuse
        // the token.
        accessToken = [[NSUserDefaults standardUserDefaults] objectForKey:@"access_token"];
    }

    if ( ! accessToken) NSLog(@"No access token set. Mapbox vector tiles won't work.");

    self.mapView = [[MGLMapView alloc] initWithFrame:self.view.bounds accessToken:accessToken];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.mapView];
    
    [self.mapView setDelegate:self];
    
    self.mapView.viewControllerForLayoutGuides = self;

    self.view.tintColor = kTintColor;
    self.navigationController.navigationBar.tintColor = kTintColor;
    self.mapView.tintColor = kTintColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"settings.png"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(showSettings)];

    UIButton *titleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [titleButton setFrame:CGRectMake(0, 0, 120, 40)];
    [titleButton setTitle:[kStyleNames firstObject] forState:UIControlStateNormal];
    [titleButton setTitleColor:kTintColor forState:UIControlStateNormal];
    [titleButton addTarget:self action:@selector(cycleStyles) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.titleView = titleButton;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"locateUser.png"]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(locateUser)];

    settings = new mbgl::Settings_NSUserDefaults();
    [self restoreState:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    id geojson = [NSJSONSerialization JSONObjectWithData:
                     [NSData dataWithContentsOfFile:
                        [[NSBundle mainBundle] pathForResource:@"features" ofType:@"json"]]
                                            options:NSJSONReadingMutableContainers
                                              error:nil];

    if (geojson && [geojson isKindOfClass:[NSDictionary class]]) {
        for (NSMutableDictionary *feature in geojson[@"features"]) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake([feature[@"geometry"][@"coordinates"][1] doubleValue],
                                                                  [feature[@"geometry"][@"coordinates"][0] doubleValue]);
            MBXAnnotation *annotation = [MBXAnnotation annotationWithLocation:c title:feature[@"properties"][@"title"] subtitle:nil];
            [self.mapView addAnnotation:annotation];
        }
    }
}

//#pragma mark MGLMapViewDelegate
//
//- (void)mapViewRegionIsChanging:(MGLMapView *)mapView
//{
//    (void)mapView;
//}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-parameter"

- (void)saveState:(NSNotification *)notification
{
    if (self.mapView && settings)
    {
        settings->longitude = self.mapView.centerCoordinate.longitude;
        settings->latitude = self.mapView.centerCoordinate.latitude;
        settings->zoom = self.mapView.zoomLevel;
        settings->bearing = self.mapView.direction;
        settings->debug = self.mapView.isDebugActive;
        settings->userTrackingMode = self.mapView.userTrackingMode;
        settings->showsUserLocation = self.mapView.showsUserLocation;
        settings->save();
    }
}

- (void)restoreState:(NSNotification *)notification
{
    if (self.mapView && settings) {
        settings->load();
        [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(settings->latitude, settings->longitude) zoomLevel:settings->zoom animated:NO];
        self.mapView.direction = settings->bearing;
        self.mapView.userTrackingMode = settings->userTrackingMode;
        self.mapView.showsUserLocation = settings->showsUserLocation;
        [self.mapView setDebugActive:settings->debug];
    }
}

#pragma clang diagnostic pop

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Actions

- (void)showSettings
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Map Settings"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Reset North", @"Reset Position", @"Toggle Debug", nil];

    [sheet showFromBarButtonItem:self.navigationItem.leftBarButtonItem animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.firstOtherButtonIndex)
    {
        [self.mapView resetNorth];
    }
    else if (buttonIndex == actionSheet.firstOtherButtonIndex + 1)
    {
        [self.mapView resetPosition];
    }
    else if (buttonIndex == actionSheet.firstOtherButtonIndex + 2)
    {
        [self.mapView toggleDebug];
    }
}

- (void)cycleStyles
{
    UIButton *titleButton = (UIButton *)self.navigationItem.titleView;

    NSString *styleName = [titleButton titleForState:UIControlStateNormal];

    if ( ! styleName)
    {
        styleName = [kStyleNames firstObject];
    }
    else
    {
        NSUInteger index = [kStyleNames indexOfObject:styleName] + 1;
        if (index == [kStyleNames count]) index = 0;
        styleName = [kStyleNames objectAtIndex:index];
    }

    [self.mapView useBundledStyleNamed:
        [[[styleName lowercaseString]
        stringByAppendingString:@"-"]
        stringByAppendingString:kStyleVersion]];

    [titleButton setTitle:styleName forState:UIControlStateNormal];
}

- (void)locateUser
{
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied)
    {
        [[[UIAlertView alloc] initWithTitle:@"Authorization Denied"
                                    message:@"Please enable location services for this app in Privacy settings."
                                   delegate:nil
                          cancelButtonTitle:nil otherButtonTitles:@"OK", nil] show];
    }
    else
    {
        self.mapView.userTrackingMode = MGLUserTrackingModeFollowWithHeading;
        self.mapView.showsUserLocation = YES;
    }
}

#pragma mark - Destruction

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (settings)
    {
        [self saveState:nil];
        delete settings;
        settings = nullptr;
    }
}

#pragma mark - MGLMapViewDelegate methods

- (NSString *)mapView:(MGLMapView *)mapView symbolNameForAnnotation:(id <MGLAnnotation>)symbolName {
    (void)mapView;
    (void)symbolName;
    return @"pin";
}

@end
