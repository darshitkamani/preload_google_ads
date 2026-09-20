import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preload_google_ads/preload_google_ads.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show instanceManager;
import 'package:preload_google_ads/src/ad_internal.dart'
    show AdManager, AdLoadState, LoadMediumNative;

/// End-to-end tests of the native retry limit: real [LoadMediumNative.loadAd]
/// calls against a fake AdMob platform channel that we can make fail or
/// succeed on demand. The 2-second retry delay is real, so these take a few
/// seconds each.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const retryDelay = Duration(milliseconds: 2400); // 2 s retry + slack
  late AdConfigData originalConfig;
  late LoadMediumNative loader;

  /// adId of every native ad request the loader has made, in order.
  final requests = <int>[];

  AdConfigData configWith(int? limit) => AdConfigData(
        adFlag: AdFlag(showAd: true, showNative: true),
        adIDs: AdIDS(nativeId: 'native-unit'),
        nativeRetryLimit: limit,
      );

  Future<void> platformEvent(int adId, String name, [Map? extra]) async {
    final codec = instanceManager.channel.codec;
    final message = codec.encodeMethodCall(
      MethodCall('onAdEvent', {'adId': adId, 'eventName': name, ...?extra}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(instanceManager.channel.name, message, (_) {});
  }

  Future<void> failLatest() => platformEvent(
        requests.last,
        'onAdFailedToLoad',
        {
          'loadAdError':
              LoadAdError(3, 'com.google.android.gms.ads', 'No fill', null),
        },
      );

  Future<void> succeedLatest() => platformEvent(requests.last, 'onAdLoaded');

  Future<void> settle([Duration d = const Duration(milliseconds: 50)]) =>
      Future.delayed(d);

  setUp(() {
    originalConfig = AdManager.instance.config;
    requests.clear();
    loader = LoadMediumNative.instance..reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
      if (call.method == 'loadNativeAd') {
        requests.add((call.arguments as Map)['adId'] as int);
      }
      return null;
    });
  });

  tearDown(() {
    loader.reset();
    AdManager.instance.config = originalConfig;
  });

  test('limit 1: request fails -> exactly one retry -> stops', () async {
    AdManager.instance.config = configWith(1);

    await loader.loadAd();
    expect(requests.length, 1);

    await failLatest();
    await settle();
    expect(requests.length, 1, reason: 'retry waits 2 s, nothing sooner');

    await settle(retryDelay);
    expect(requests.length, 2, reason: 'the one retry');

    await failLatest();
    await settle(const Duration(seconds: 6));
    expect(requests.length, 2, reason: 'no third, fourth, ... request');
    expect(loader.state, AdLoadState.failed);
    expect(loader.ads, isEmpty);
  });

  test('limit 1: a later request (another screen) is served and retried once',
      () async {
    AdManager.instance.config = configWith(1);

    // First screen: fails, retries once, fails again -> gives up.
    await loader.loadAd();
    await failLatest();
    await settle(retryDelay);
    await failLatest();
    await settle();
    expect(requests.length, 2);

    // Second screen asks again: a brand-new request, which succeeds.
    await loader.loadAd();
    expect(requests.length, 3);
    await succeedLatest();
    await settle();

    expect(loader.ads.length, 1, reason: 'the ad is now preloaded');
    expect(loader.state, AdLoadState.ready);
    await settle(retryDelay);
    expect(requests.length, 3, reason: 'nothing more once it has loaded');
  });

  test('limit 1: the retry can succeed', () async {
    AdManager.instance.config = configWith(1);

    await loader.loadAd();
    await failLatest();
    await settle(retryDelay);
    expect(requests.length, 2);
    await succeedLatest();
    await settle();

    expect(loader.ads.length, 1);
    expect(loader.state, AdLoadState.ready);
    expect(loader.retriesUsedForRequest, 0);
  });

  test('limit 1: a request during the pending retry takes its place', () async {
    AdManager.instance.config = configWith(1);

    await loader.loadAd();
    await failLatest();
    await settle(); // retry timer now pending

    await loader.loadAd(); // another screen asks before the retry fires
    expect(requests.length, 2, reason: 'served immediately');

    await failLatest();
    await settle(const Duration(seconds: 6));
    expect(requests.length, 2,
        reason: 'the cancelled timer must not fire a duplicate request, and '
            'the retry budget is already spent');
  });

  test('limit 1: repeated failure chains never exceed 2 requests each',
      () async {
    AdManager.instance.config = configWith(1);

    for (var chain = 1; chain <= 4; chain++) {
      final before = requests.length;
      await loader.loadAd();
      await failLatest();
      await settle(retryDelay);
      await failLatest();
      await settle(const Duration(milliseconds: 300));
      expect(requests.length - before, 2, reason: 'chain $chain');
    }
    expect(requests.length, 8);
  });

  test('limit 2: two retries, then stops', () async {
    AdManager.instance.config = configWith(2);

    await loader.loadAd();
    await failLatest();
    await settle(retryDelay);
    await failLatest();
    await settle(retryDelay);
    await failLatest();
    await settle(const Duration(seconds: 6));

    expect(requests.length, 3);
  });

  test('null (default): original indefinite retrying is unchanged', () async {
    AdManager.instance.config = configWith(null);

    await loader.loadAd();
    await failLatest(); // -> retry after 2 s
    await settle(retryDelay);
    expect(requests.length, 2);
    await failLatest(); // -> retry after 4 s
    await settle(const Duration(milliseconds: 4400));
    expect(requests.length, 3);
    await failLatest(); // -> recovery retry after 15 s, i.e. it keeps going
    expect(loader.state, AdLoadState.failed);
    expect(loader.retryAttempts, 3, reason: 'legacy cycle resets and repeats');
  });
}
