#import "IPFTestRunner.h"
#import "IPFTestRunnerConfiguration.h"

#import "../iperf3/iperf_config.h"
#import "../iperf3/iperf_api.h"
#import "../iperf3/iperf.h"
#import "../iperf3/queue.h"

static __unsafe_unretained IPFTestRunner *s_currentTestRunner;

@interface IPFTestRunner ()

- (void)dispatchStatus:(IPFTestRunnerStatus)status;

@end

static IPFTestRunnerStatus IPFTestRunnerStatusWithErrorState(IPFTestRunnerStatus status, IPFTestRunnerErrorState errorState)
{
  status.errorState = errorState;

  return status;
}

static IPFTestRunnerErrorState IPFTestRunnerErrorStateFromIPerfError(int error)
{
  switch (error) {
    case IENONE:
      return IPFTestRunnerErrorStateNoError;

    case IECONNECT:
      return IPFTestRunnerErrorStateCannotConnectToTheServer;

    case IEACCESSDENIED:
      return IPFTestRunnerErrorStateServerIsBusy;

    case IESTREAMREAD:
    case IESTREAMCLOSE:
      return IPFTestRunnerErrorStateNoError;

    default:
      return IPFTestRunnerErrorStateUnknown + error;
  }
}

static void vc_reporter_callback(struct iperf_test *test)
{
  struct iperf_stream *stream = NULL;
  struct iperf_interval_results *interval_results = NULL;
  iperf_size_t bytes = 0;
  int total_packets = 0, lost_packets = 0;
  double avg_jitter = 0.0, lost_percent = 0.0;
  int stream_count = 0;

  SLIST_FOREACH(stream, &test->streams, streams) {
    stream_count++;
    interval_results = TAILQ_LAST(&stream->result->interval_results, irlisthead);
    if (!interval_results) {
      continue;
    }
    iperf_size_t b = interval_results->bytes_transferred;
    bytes += b;

    if (test->protocol->id != Ptcp) {
      total_packets += interval_results->interval_packet_count;
      lost_packets += interval_results->interval_cnt_error;
      avg_jitter += interval_results->jitter;
    }
  }

  stream = SLIST_FIRST(&test->streams);
  if (!stream) { return; }

  interval_results = TAILQ_LAST(&stream->result->interval_results, irlisthead);
  if (!interval_results || interval_results->interval_duration <= 0.0) {
    return;
  }

  double bandwidth = (double)bytes / (double)interval_results->interval_duration;
  if (test->num_streams > 0) {
    avg_jitter /= test->num_streams;
  }

  if (total_packets > 0) {
    lost_percent = 100.0 * lost_packets / total_packets;
  }

  IPFTestRunnerStatus status;
  status.errorState = IPFTestRunnerErrorStateNoError;
  status.running = YES;
  status.bandwidth = bandwidth * 8 / 1000000;
  status.jitter = (CGFloat)(avg_jitter * 1000.0);
  status.packetLoss = (CGFloat)lost_percent;

  if (test->timer) {
    CGFloat test_duration = (CGFloat)test->timer->usecs / SEC_TO_US;
    CGFloat test_elapsed = test_duration - (test->timer->time.secs - test->stats_timer->time.secs) - 1.0;
    status.progress = test_elapsed / test_duration;
  } else {
    status.progress = 1.0;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [s_currentTestRunner dispatchStatus:status];
  });
}

@implementation IPFTestRunner {
  IPFTestRunnerCallback _callback;
  struct iperf_test *_test;
}

- (id)initWithConfiguration:(IPFTestRunnerConfiguration *)configuration
{
  self = [super init];

  if (self) {
    _configuration = configuration;
  }

  return self;
}

- (void)dealloc
{
  NSAssert(s_currentTestRunner == nil && _callback == nil, @"Test should not be running");
}

- (void)startTest:(IPFTestRunnerCallback)callback
{
  IPFTestRunnerConfiguration *configuration = _configuration;
  IPFTestRunnerStatus status;
  struct iperf_test *test = iperf_new_test();
  NSString *streamFilePathTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"iperf3.XXXXXX"];
  __unsafe_unretained IPFTestRunner *blockSelf = self;

  NSAssert([[NSThread currentThread] isMainThread], @"Tests need to run on the main thread");
  status.bandwidth = 0.0;
  status.running = NO;
  status.progress = 0.0;
  status.jitter = 0.0;
  status.packetLoss = 0.0;
  status.errorState = IPFTestRunnerErrorStateNoError;

  if (!test) {
    callback(IPFTestRunnerStatusWithErrorState(status, IPFTestRunnerErrorStateCouldntInitializeTest));
    return;
  }

  if (iperf_defaults(test) < 0) {
    callback(IPFTestRunnerStatusWithErrorState(status, IPFTestRunnerErrorStateCouldntInitializeTest));
    return;
  }

  if (configuration.type == IPFTestRunnerConfigurationTypeServer) {
    iperf_set_test_role(test, 's');
  } else {
    iperf_set_test_role(test, 'c');
    iperf_set_test_num_streams(test, (int)configuration.streams);

    if (configuration.useUDP) {
      set_protocol(test, Pudp);
      test->settings->blksize = DEFAULT_UDP_BLKSIZE;
      test->settings->rate = configuration.udpBandwidth;
    }

    if (configuration.type == IPFTestRunnerConfigurationTypeDownload) {
      iperf_set_test_reverse(test, 1);
    }
  }

  {
    char *hostname = (char *)[configuration.hostname cStringUsingEncoding:NSASCIIStringEncoding];

    if (hostname != NULL) {
      iperf_set_test_server_hostname(test, hostname);
    }
  }

  iperf_set_test_server_port(test, (int)configuration.port);
  iperf_set_test_duration(test, (int)configuration.duration);

  iperf_set_test_template(test, (char *)[streamFilePathTemplate cStringUsingEncoding:NSUTF8StringEncoding]);
  test->settings->connect_timeout = 3000;
  i_errno = IENONE;

  test->reporter_callback = vc_reporter_callback;
  _test = test;
  NSAssert(s_currentTestRunner == nil, @"Test is already running");
  s_currentTestRunner = self;
  NSAssert(_callback == nil, @"Test is already running");
  _callback = callback;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
    if (configuration.type == IPFTestRunnerConfigurationTypeServer) {
      iperf_run_server(test);
    } else {
      iperf_run_client(test);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      IPFTestRunnerStatus callbackStatus = status;
      IPFTestRunnerCallback callback = blockSelf->_callback;

      s_currentTestRunner = nil;
      blockSelf->_callback = nil;
      blockSelf->_test = NULL;
      callbackStatus.running = NO;
      callbackStatus.progress = 1.0;
      callbackStatus.errorState = IPFTestRunnerErrorStateFromIPerfError(i_errno);
      iperf_free_test(test);
      callback(callbackStatus);
    });
  });
}

- (void)stopTest
{
  if (_test != NULL) {
    _test->done = 1;
  }
}

- (void)dispatchStatus:(IPFTestRunnerStatus)status
{
  NSAssert([[NSThread currentThread] isMainThread], @"Tests need to run on the main thread");
  _callback(status);
}

@end
