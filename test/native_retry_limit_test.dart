import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preload_google_ads/preload_google_ads.dart';
// AdManager and the loaders are internal, but the tests drive them directly.
import 'package:preload_google_ads/src/ad_internal.dart'
    show AdManager, AdLoadState, LoadMediumNative;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdConfigData originalConfig;
  late LoadMediumNative loader;
  var retries = 0;

  void useLimit(int? limit) {
    AdManager.instance.config = AdConfigData(nativeRetryLimit: limit);
  }

  setUp(() {
    originalConfig = AdManager.instance.config;
    loader = LoadMediumNative.instance..reset();
    retries = 0;
  });
  tearDown(() {
    loader.reset();
    AdManager.instance.config = originalConfig;
  });

  group('nativeRetryLimit', () {
    test('1: a failed request is retried once, then it stops', () {
      useLimit(1);
      fakeAsync((async) {
        loader.handleFailureAndRetry('err', onRetry: () => retries++);
        expect(retries, 0, reason: 'the retry waits 2 seconds');

        async.elapse(const Duration(seconds: 2));
        expect(retries, 1);

        // The retry fails too: give up, nothing more is scheduled.
        loader.handleFailureAndRetry('err', onRetry: () => retries++);
        async.elapse(const Duration(minutes: 5));
        expect(retries, 1);
        expect(loader.state, AdLoadState.failed);
      });
    });

    test('after giving up, the next request gets its own retry', () {
      useLimit(1);
      fakeAsync((async) {
        loader.handleFailureAndRetry('err', onRetry: () => retries++);
        async.elapse(const Duration(seconds: 2));
        loader.handleFailureAndRetry('err', onRetry: () => retries++);
        async.elapse(const Duration(minutes: 1));
        expect(retries, 1);

        // A later request (say, another screen) fails again.
        loader.handleFailureAndRetry('err', onRetry: () => retries++);
        async.elapse(const Duration(seconds: 2));
        expect(retries, 2);
      });
    });

    test('a success clears the retry count', () {
      useLimit(1);
      fakeAsync((async) {
        loader.handleFailureAndRetry('err', onRetry: () => retries++);
        async.elapse(const Duration(seconds: 2));
        expect(loader.retriesUsedForRequest, 1);

        loader.handleLoadSuccess();

        expect(loader.retriesUsedForRequest, 0);
      });
    });

    test('null keeps the original indefinite retrying', () {
      useLimit(null);
      fakeAsync((async) {
        for (var i = 0; i < 6; i++) {
          loader.handleFailureAndRetry('err', onRetry: () => retries++);
          async.elapse(const Duration(seconds: 20));
        }
        expect(retries, 6);
      });
    });
  });
}
