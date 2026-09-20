import '../ad_internal.dart';

/// A rewarded interstitial that is **requested at the moment it is needed**
/// (for example when the user taps "download") -- nothing is preloaded and
/// nothing is kept once it has been shown.
///
/// Two steps, so the caller can show its own loading UI in between:
///
/// ```dart
/// final loader = OnDemandRewardedInterstitialAd(adUnitId: 'ca-app-pub-.../...');
/// showSpinner();
/// final ad = await loader.load();          // null if it failed / timed out
/// hideSpinner();
/// if (ad != null) await loader.show(ad);   // completes once dismissed
/// runTheActualAction();
/// ```
///
/// This is a standalone class: it does not touch [RewardInterAd] or any
/// [AdFlag] toggle, so it can be used instead of the preloading rewarded
/// interstitial (turn that one off with `AdFlag.showRewardedInterstitial:
/// false`).
class OnDemandRewardedInterstitialAd {
  /// The AdMob ad unit id requested for every load.
  final String adUnitId;

  /// How long [load] waits for the ad before giving up.
  final Duration loadTimeout;

  /// Creates a loader for [adUnitId]. [load] gives up after [loadTimeout].
  OnDemandRewardedInterstitialAd({
    required this.adUnitId,
    this.loadTimeout = const Duration(seconds: 8),
  });

  /// Requests a fresh ad. Completes with `null` if the request failed or the
  /// ad did not arrive within [loadTimeout]; an ad that arrives after that is
  /// disposed rather than kept.
  Future<RewardedInterstitialAd?> load() {
    final completer = Completer<RewardedInterstitialAd?>();
    final timeout = Timer(loadTimeout, () {
      if (!completer.isCompleted) {
        AppLogger.warn('On-demand rewarded interstitial timed out.');
        completer.complete(null);
      }
    });
    try {
      RewardedInterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            timeout.cancel();
            AdStats.instance.rewardedInterLoad.value++;
            if (completer.isCompleted) {
              ad.dispose();
            } else {
              ad.setImmersiveMode(true);
              completer.complete(ad);
            }
          },
          onAdFailedToLoad: (error) {
            timeout.cancel();
            AdStats.instance.rewardedInterFailed.value++;
            AppLogger.error(
                'On-demand rewarded interstitial failed to load: $error');
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (error) {
      timeout.cancel();
      AppLogger.error('On-demand rewarded interstitial load threw: $error');
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  /// Shows [ad] and completes once it has been dismissed (or failed to show).
  /// [onReward] is called if the user earns the reward.
  Future<void> show(
    RewardedInterstitialAd ad, {
    void Function(AdWithoutView ad, RewardItem reward)? onReward,
  }) {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    ad.fullScreenContentCallback =
        FullScreenContentCallback<RewardedInterstitialAd>(
      onAdImpression: (_) => AdStats.instance.rewardedInterImp.value++,
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.error(
            'On-demand rewarded interstitial failed to show: $error');
        ad.dispose();
        finish();
      },
    );
    ad.show(onUserEarnedReward: (ad, reward) => onReward?.call(ad, reward));
    return done.future;
  }
}
