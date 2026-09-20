import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show instanceManager;
import 'package:preload_google_ads/preload_google_ads.dart';

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
}
