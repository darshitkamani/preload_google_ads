import '../ad_internal.dart';

/// A rewarded video ad that is **requested at the moment it is needed** (for
/// example when the user taps "watch an ad to earn coins") -- nothing is
/// preloaded and nothing is kept once it has been shown.
///
/// Two steps, so the caller can show its own loading state in between:
///
/// ```dart
/// final loader = OnDemandRewardedAd(adUnitId: 'ca-app-pub-.../...');
/// setState(() => loading = true);
/// final ad = await loader.load();              // null if it failed / timed out
/// final earned = ad == null
///     ? false
///     : await loader.show(ad, onReward: (_, reward) => giveCoins());
/// setState(() => loading = false);
/// ```
///
/// This is a standalone class: it does not touch [RewardAd] or the
/// [AdFlag.showRewarded] toggle, so it can be used instead of the preloading
/// rewarded ad (turn that one off with `AdFlag.showRewarded: false`). The one
/// switch it does honor is the master [AdFlag.showAd]: while that is off
/// [load] makes no request and completes with `null`.
class OnDemandRewardedAd {
  /// The AdMob ad unit id requested for every load.
  final String adUnitId;

  /// How long [load] waits for the ad before giving up.
  final Duration loadTimeout;

  /// Creates a loader for [adUnitId]. [load] gives up after [loadTimeout].
  OnDemandRewardedAd({
    required this.adUnitId,
    this.loadTimeout = const Duration(seconds: 8),
  });

  /// Requests a fresh ad. Completes with `null` if the request failed, ads are
  /// off, or the ad did not arrive within [loadTimeout]; an ad that arrives
  /// after that is disposed rather than kept.
  Future<RewardedAd?> load() {
    if (!shouldShowAd) return Future.value(null);
    final completer = Completer<RewardedAd?>();
    final timeout = Timer(loadTimeout, () {
      if (!completer.isCompleted) {
        AppLogger.warn('On-demand rewarded ad timed out.');
        completer.complete(null);
      }
    });
    try {
      AdStats.instance.rewardedReq.value++;
      RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            timeout.cancel();
            AdStats.instance.rewardedLoad.value++;
            if (completer.isCompleted) {
              ad.dispose();
            } else {
              ad.setImmersiveMode(true);
              completer.complete(ad);
            }
          },
          onAdFailedToLoad: (error) {
            timeout.cancel();
            AdStats.instance.rewardedFailed.value++;
            AppLogger.error('On-demand rewarded ad failed to load: $error');
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (error) {
      timeout.cancel();
      AppLogger.error('On-demand rewarded ad load threw: $error');
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  /// Shows [ad] and completes once it has been dismissed (or failed to show),
  /// with `true` if the user earned the reward. [onReward] is called at the
  /// moment the reward is earned.
  Future<bool> show(
    RewardedAd ad, {
    void Function(AdWithoutView ad, RewardItem reward)? onReward,
  }) {
    final done = Completer<bool>();
    var earned = false;
    void finish() {
      if (!done.isCompleted) done.complete(earned);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdImpression: (_) => AdStats.instance.rewardedImp.value++,
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.error('On-demand rewarded ad failed to show: $error');
        ad.dispose();
        finish();
      },
    );
    ad.show(
      onUserEarnedReward: (ad, reward) {
        earned = true;
        onReward?.call(ad, reward);
      },
    );
    return done.future;
  }
}
