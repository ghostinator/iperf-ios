#import "IPFTestRunnerViewController.h"
#import "IPFTestRunner.h"
#import "IPFTestRunnerConfiguration.h"
#import "IPFIcon.h"
#import "IPFHelpViewController.h"

static int getTestDuration(NSUInteger selectedSegmentIndex)
{
  switch (selectedSegmentIndex) {
    case 0:
      return 10;

    case 1:
      return 30;

    case 2:
      return 300;

    default:
      return 10;
  }
}

static NSUInteger getUDPBandwidth(NSUInteger selectedSegmentIndex)
{
  switch (selectedSegmentIndex) {
    case 0: return   1000000;
    case 1: return   5000000;
    case 2: return  10000000;
    case 3: return  50000000;
    case 4: return 100000000;
    default: return  1000000;
  }
}

@interface IPFTestRunnerViewController ()

@property (strong, nonatomic) IPFTestRunner *testRunner;

@end

@implementation IPFTestRunnerViewController {
  CGFloat _averageBandwidthTotal;
  NSUInteger _averageBandwidthCount;
  CGFloat _maxBandwidth;
  CGFloat _minBandwidth;
  NSMutableArray *_intervalResults;
  NSString *_testHostname;
  NSUInteger _testPort;
  BOOL _testWasUDP;
  NSUInteger _testDuration;
  NSUInteger _intervalIndex;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];

  if (self != nil) {
    self.title = NSLocalizedString(@"iPerf", @"Main screen title");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Help", @"Help start button name")
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(showHelp)];
    [self showStartButton:YES];
  }

  return self;
}

- (IBAction)showHelp
{
  IPFHelpViewController *helpViewController = [[IPFHelpViewController alloc] initWithNibName:nil bundle:nil];

  [self.navigationController pushViewController:helpViewController animated:YES];
}

- (void)showStartButton:(BOOL)showStartButton
{
  NSString *title = showStartButton ? NSLocalizedString(@"Start", @"Test start button name") : NSLocalizedString(@"Stop", @"Test stop button name");
  UIBarButtonItem *buttonItem = [[UIBarButtonItem alloc] initWithTitle:title
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(startStopTest)];

  if (!showStartButton) {
    buttonItem.tintColor = [UIColor redColor];
  }

  self.navigationItem.rightBarButtonItem = buttonItem;
}

- (void)viewDidLoad
{
  [self restoreTestSettings];
}

- (void)restoreTestSettings
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *hostname = [defaults stringForKey:@"IPFTestHostname"];
  NSNumber *port = [defaults objectForKey:@"IPFTestPort"];

  if ([hostname length] > 0 && [port unsignedIntegerValue] > 0) {
    self.addressTextField.text = hostname;
    self.portTextField.text = [port stringValue];
  }
}

- (void)saveTestSettings
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *hostname = self.addressTextField.text;
  NSNumber *port = [NSNumber numberWithUnsignedInteger:(NSUInteger)[self.portTextField.text integerValue]];

  if ([hostname length] > 0 && [port unsignedIntegerValue] > 0) {
    [defaults setObject:hostname forKey:@"IPFTestHostname"];
    [defaults setObject:port forKey:@"IPFTestPort"];
    [defaults synchronize];
  }
}

- (void)startStopTest
{
  IPFTestRunner *testRunner = self.testRunner;

  if (testRunner) {
    [testRunner stopTest];
  } else {
    [self startTest];
  }
}

- (IBAction)udpSwitchChanged:(id)sender
{
  BOOL isOn = self.udpSwitch.on;
  self.udpBandwidthLabel.hidden = !isOn;
  self.udpBandwidthSelector.hidden = !isOn;
}

- (void)startTest
{
  NSUInteger udpBandwidth = getUDPBandwidth(self.udpBandwidthSelector.selectedSegmentIndex);
  IPFTestRunnerConfiguration *configuration = [[IPFTestRunnerConfiguration alloc] initWithHostname:self.addressTextField.text
                                                                                              port:[self.portTextField.text intValue]
                                                                                          duration:getTestDuration(self.testDurationSlider.selectedSegmentIndex)
                                                                                           streams:[self.streamsSlider selectedSegmentIndex] + 1
                                                                                              type:[self.transmitModeSlider selectedSegmentIndex]
                                                                                           useUDP:self.udpSwitch.on
                                                                                     udpBandwidth:udpBandwidth];
  IPFTestRunner *testRunner = [[IPFTestRunner alloc] initWithConfiguration:configuration];
  UIApplication *application = [UIApplication sharedApplication];
  __block UIBackgroundTaskIdentifier backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
    [application endBackgroundTask:backgroundTask];
    backgroundTask = UIBackgroundTaskInvalid;
  }];

  _testHostname = self.addressTextField.text;
  _testPort = [self.portTextField.text integerValue];
  _testWasUDP = self.udpSwitch.on;
  _testDuration = getTestDuration(self.testDurationSlider.selectedSegmentIndex);
  _intervalResults = [NSMutableArray array];
  _intervalIndex = 0;

  self.testRunner = testRunner;
  [self showStartButton:NO];
  self.addressTextField.enabled = NO;
  self.portTextField.enabled = NO;
  self.transmitModeSlider.enabled = NO;
  self.streamsSlider.enabled = NO;
  self.testDurationSlider.enabled = NO;
  self.udpSwitch.enabled = NO;
  self.udpBandwidthSelector.enabled = NO;
  self.bandwidthLabel.text = @"...";
  self.averageBandwidthLabel.text = @"";
  self.jitterLabel.text = @"";
  self.jitterLabel.hidden = YES;
  self.packetLossLabel.text = @"";
  self.packetLossLabel.hidden = YES;
  self.progressView.progress = 0.0;
  self.progressView.hidden = YES;
  [application setNetworkActivityIndicatorVisible:YES];
  _averageBandwidthTotal = 0;
  _averageBandwidthCount = 0;
  _maxBandwidth = CGFLOAT_MIN;
  _minBandwidth = CGFLOAT_MAX;

  [testRunner startTest:^(IPFTestRunnerStatus status) {
    switch (status.errorState) {
      case IPFTestRunnerErrorStateNoError:
        break;

      case IPFTestRunnerErrorStateCouldntInitializeTest:
        [self showAlert:NSLocalizedString(@"Error initializing the test", nil)];
        break;

      case IPFTestRunnerErrorStateCannotConnectToTheServer:
        [self showAlert:NSLocalizedString(@"Cannot connect to the server, please check that the server is running", nil)];
        break;

      case IPFTestRunnerErrorStateServerIsBusy:
        [self showAlert:NSLocalizedString(@"Server is busy, please retry later", nil)];
        break;

      default:
        [self showAlert:[NSString stringWithFormat:NSLocalizedString(@"Unknown error %d running the test", nil), status.errorState]];
        break;
    }

    if (status.running == NO) {
      [self showStartButton:YES];
      self.addressTextField.enabled = YES;
      self.portTextField.enabled = YES;
      self.transmitModeSlider.enabled = YES;
      self.streamsSlider.enabled = YES;
      self.testDurationSlider.enabled = YES;
      self.udpSwitch.enabled = YES;
      self.udpBandwidthSelector.enabled = YES;
      self.progressView.hidden = YES;
      self.testRunner = nil;
      [application setNetworkActivityIndicatorVisible:NO];
      [application endBackgroundTask:backgroundTask];

      if (status.errorState == IPFTestRunnerErrorStateNoError || status.errorState == IPFTestRunnerErrorStateServerIsBusy) {
        if (self->_averageBandwidthTotal) {
          self.bandwidthLabel.text = [NSString stringWithFormat:@"%.0f Mbits/s", self->_averageBandwidthTotal / (CGFloat)self->_averageBandwidthCount];
          self.averageBandwidthLabel.text = [NSString stringWithFormat:@"min: %.0f max: %.0f", self->_minBandwidth, self->_maxBandwidth];
          self.progressView.hidden = NO;
          [self showExportButton];
        } else {
          self.bandwidthLabel.text = @"";
        }

        [self saveTestSettings];
      }
    } else {
      CGFloat bandwidth = status.bandwidth;

      self->_averageBandwidthTotal += bandwidth;
      self->_averageBandwidthCount++;
      self->_intervalIndex++;
      self.progressView.hidden = NO;

      if (bandwidth < self->_minBandwidth) {
        self->_minBandwidth = bandwidth;
      }

      if (bandwidth > self->_maxBandwidth) {
        self->_maxBandwidth = bandwidth;
      }

      CGFloat startSec = (CGFloat)(self->_intervalIndex - 1);
      CGFloat endSec = (CGFloat)self->_intervalIndex;
      NSString *intervalLine;
      if (configuration.useUDP) {
        intervalLine = [NSString stringWithFormat:@"[  4] %5.2f-%5.2f sec  %6.2f MBytes  %6.2f Mbits/sec  %6.3f ms  %ld/%ld (%.2f%%)",
                        startSec, endSec,
                        bandwidth / 8.0,
                        bandwidth,
                        status.jitter,
                        (long)0, (long)0,
                        status.packetLoss];
      } else {
        intervalLine = [NSString stringWithFormat:@"[  4] %5.2f-%5.2f sec  %6.2f MBytes  %6.2f Mbits/sec",
                        startSec, endSec,
                        bandwidth / 8.0,
                        bandwidth];
      }
      [self->_intervalResults addObject:intervalLine];

      self.bandwidthLabel.text = [NSString stringWithFormat:@"%.0f Mbits/s", status.bandwidth];
      self.averageBandwidthLabel.text = [NSString stringWithFormat:@"avg: %.0f min: %.0f max: %.0f", self->_averageBandwidthTotal / (CGFloat)self->_averageBandwidthCount, self->_minBandwidth, self->_maxBandwidth];

      if (configuration.useUDP) {
        self.jitterLabel.hidden = NO;
        self.packetLossLabel.hidden = NO;
        self.jitterLabel.text = [NSString stringWithFormat:@"jitter: %.2f ms", status.jitter];
        self.packetLossLabel.text = [NSString stringWithFormat:@"packet loss: %.1f%%", status.packetLoss];
      }

      [self.progressView setProgress:status.progress animated:YES];
    }
  }];
}

- (void)showExportButton
{
  UIBarButtonItem *exportItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                              target:self
                                                                              action:@selector(exportResults)];
  self.navigationItem.leftBarButtonItem = exportItem;
}

- (void)exportResults
{
  NSMutableString *output = [NSMutableString string];
  NSString *protocol = _testWasUDP ? @"UDP" : @"TCP";
  CGFloat avgBandwidth = _averageBandwidthCount > 0 ? _averageBandwidthTotal / (CGFloat)_averageBandwidthCount : 0;

  [output appendFormat:@"------------------------------------------------------------\n"];
  [output appendFormat:@"Client connecting to %@, %@ port %lu\n", _testHostname, protocol, (unsigned long)_testPort];
  [output appendFormat:@"------------------------------------------------------------\n"];

  if (_testWasUDP) {
    [output appendString:@"[ ID] Interval           Transfer    Bandwidth       Jitter    Lost/Total (%%)\n"];
  } else {
    [output appendString:@"[ ID] Interval           Transfer    Bandwidth\n"];
  }

  for (NSString *line in _intervalResults) {
    [output appendFormat:@"%@\n", line];
  }

  [output appendFormat:@"------------------------------------------------------------\n"];
  [output appendFormat:@"[  4]  0.00-%5.2f sec  avg %.2f Mbits/sec  min %.0f  max %.0f Mbits/sec\n",
   (CGFloat)_testDuration, avgBandwidth, _minBandwidth, _maxBandwidth];

  UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[output] applicationActivities:nil];
  [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)showAlert:(NSString *)alertText
{
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:alertText message:nil preferredStyle:UIAlertControllerStyleAlert];

  [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:NULL]];
  [self presentViewController:alertController animated:YES completion:NULL];
  self.bandwidthLabel.text = @"";
  self.averageBandwidthLabel.text = @"";
  self.progressView.hidden = YES;
}

@end