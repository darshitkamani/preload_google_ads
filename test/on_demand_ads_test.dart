import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show instanceManager;
import 'package:preload_google_ads/preload_google_ads.dart';
// AdManager is internal, but the tests need to swap its config.
import 'package:preload_google_ads/src/ad_internal.dart' show AdManager;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Swallows every google_mobile_ads platform call: ad requests are accepted
  // but never answered, i.e. an ad that stays "loading".
  final loadCalls = <String>[];
  setUp(() {
    loadCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      // The plugin's own channel: it uses a custom codec, so a plain
      // MethodChannel with the same name could not decode its messages.
      instanceManager.channel,
      (call) async {
        if (call.method.startsWith('load')) loadCalls.add(call.method);
        return null;
      },
    );
  });

  group('master showAd switch', () {
    late AdConfigData originalConfig;
    setUp(() {
      originalConfig = AdManager.instance.config;
      AdManager.instance.config = AdConfigData(adFlag: AdFlag(showAd: false));
    });
    tearDown(() => AdManager.instance.config = originalConfig);

    test('interstitial neither counts nor loads', () {
      final ad = OnDemandInterstitialAd(adUnitId: 'unit', interval: 3);

      for (var i = 0; i < 6; i++) {
        ad.onNavigation();
      }

      expect(ad.navigationCount, 0);
      expect(ad.isLoading, isFalse);
      expect(loadCalls, isEmpty);
    });

    test('rewarded interstitial makes no request', () async {
      final loader = OnDemandRewardedInterstitialAd(adUnitId: 'unit');

      expect(await loader.load(), isNull);
      expect(loadCalls, isEmpty);
    });

    test('app open makes no request', () async {
      final appOpen = OnDemandAppOpenAd(adUnitId: 'unit');

      expect(await appOpen.loadAndShow(), isFalse);
      expect(loadCalls, isEmpty);
    });
  });

  group('OnDemandInterstitialAd', () {
    test('does nothing until one navigation before it is due', () {
      final ad = OnDemandInterstitialAd(adUnitId: 'unit', interval: 5);

      for (var i = 1; i <= 3; i++) {
        ad.onNavigation();
        expect(ad.navigationCount, i);
        expect(ad.isLoading, isFalse, reason: 'navigation $i is too early');
      }
      expect(loadCalls, isEmpty);
    });

    test('starts loading on navigation 4 of 5, not before', () {
      final ad = OnDemandInterstitialAd(adUnitId: 'unit', interval: 5);

      for (var i = 0; i < 4; i++) {
        ad.onNavigation();
      }

      expect(ad.isLoading, isTrue);
      expect(ad.navigationCount, 4);
    });

    test('still loading when due: keeps counting instead of resetting', () {
      final ad = OnDemandInterstitialAd(adUnitId: 'unit', interval: 5);

      for (var i = 0; i < 6; i++) {
        ad.onNavigation();
      }

      // Nothing was shown (no ad ever arrived), so the count keeps growing --
      // the ad shows on the first navigation after it becomes ready.
      expect(ad.navigationCount, 6);
      expect(ad.isAdLoaded, isFalse);
    });

    test('a load in flight is not requested twice', () {
      final ad = OnDemandInterstitialAd(adUnitId: 'unit', interval: 3);

      for (var i = 0; i < 6; i++) {
        ad.onNavigation();
      }

      expect(loadCalls.length, 1);
    });

    test('reset clears the count', () {
      final ad = OnDemandInterstitialAd(adUnitId: 'unit', interval: 5);
      ad.onNavigation();
      ad.onNavigation();

      ad.reset();

      expect(ad.navigationCount, 0);
    });
  });

  group('OnDemandRewardedInterstitialAd', () {
    test('load gives up with null after the timeout', () async {
      final loader = OnDemandRewardedInterstitialAd(
        adUnitId: 'unit',
        loadTimeout: const Duration(milliseconds: 50),
      );

      expect(await loader.load(), isNull);
      expect(loadCalls.length, 1);
    });
  });

  group('OnDemandAppOpenAd', () {
    test('gives up without showing when the ad does not arrive in time',
        () async {
      final appOpen = OnDemandAppOpenAd(
        adUnitId: 'unit',
        loadTimeout: const Duration(milliseconds: 50),
      );

      expect(await appOpen.loadAndShow(), isFalse);
      expect(loadCalls.length, 1);
      expect(appOpen.isBusy, isFalse);
    });

    test('a call while one is in progress does nothing', () async {
      final appOpen = OnDemandAppOpenAd(
        adUnitId: 'unit',
        loadTimeout: const Duration(milliseconds: 50),
      );

      final first = appOpen.loadAndShow();
      expect(appOpen.isBusy, isTrue);
      expect(await appOpen.loadAndShow(), isFalse);
      await first;

      expect(loadCalls.length, 1);
    });

    test('timeout argument overrides the default for one call', () async {
      final appOpen = OnDemandAppOpenAd(
        adUnitId: 'unit',
        loadTimeout: const Duration(minutes: 5),
      );

      expect(
        await appOpen.loadAndShow(timeout: const Duration(milliseconds: 50)),
        isFalse,
      );
    });

    test('makes a fresh request for every call, never a cached ad', () async {
      final appOpen = OnDemandAppOpenAd(
        adUnitId: 'unit',
        loadTimeout: const Duration(milliseconds: 30),
      );

      await appOpen.loadAndShow();
      await appOpen.loadAndShow();

      expect(loadCalls.length, 2);
    });
  });
}
