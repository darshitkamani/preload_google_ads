import '../ad_internal.dart';

/// An interstitial that is **loaded just before it is due** instead of being
/// kept preloaded.
///
/// It is shown on every [interval]th call to [onNavigation], and the load is
/// started one call earlier. With `interval: 5` the 4th navigation starts the
/// load and the 5th shows the ad. If the ad is still loading on the 5th, the
/// next navigation shows it instead (and the one after that, if it is still
/// not ready, and so on). Showing resets the count, so the following cycle
/// loads on its 4th navigation and shows on its 5th. A failed load is simply
/// retried on the next navigation; nothing is reloaded in the background.
///
/// This is a standalone class: it does not touch [InterAd], the counters in
/// [AdCounter] or any of the [AdFlag] toggles, so it can be used instead of
/// the preloading interstitial (turn that one off with
/// `AdFlag.showInterstitial: false`) or alongside other formats. The one
/// switch it does honor is the master [AdFlag.showAd]: while that is off it
/// counts nothing and never loads or shows an ad.
///
/// ```dart
/// final inter = OnDemandInterstitialAd(adUnitId: 'ca-app-pub-.../...', interval: 5);
/// // call on every screen change / tab switch:
/// inter.onNavigation();
/// ```
class OnDemandInterstitialAd {
  /// The AdMob ad unit id requested for every load.
  final String adUnitId;

  /// Show an ad on every [interval]th navigation. Values of 1 or less load on
  /// the first navigation and show on the next one.
  final int interval;

  /// Creates a controller for [adUnitId] that shows every [interval]th
  /// navigation.
  OnDemandInterstitialAd({required this.adUnitId, required this.interval});

  /// How long a loaded-but-unshown ad is kept. Kept well inside AdMob's
  /// 4-hour limit; an older ad is dropped and requested again.
  static const Duration maxAge = Duration(hours: 3);

  int _navigations = 0;
  InterstitialAd? _ad;
  DateTime? _loadedAt;
  bool _loading = false;
  bool _showing = false;

  /// Navigations counted since the last time an ad was shown.
  int get navigationCount => _navigations;

  /// Whether an ad is loaded and ready to be shown right now.
  bool get isAdLoaded => _isReady;

  /// Whether an ad request is currently in flight.
  bool get isLoading => _loading;

  /// Reports one screen navigation / tab change: counts it, starts loading one
  /// step before the ad is due, and shows the ad once it is due and ready.
  void onNavigation() {
    if (!shouldShowAd || _showing) return;
    _navigations++;
    if (_navigations < interval - 1) return;

    if (_navigations >= interval && _isReady) {
      _show();
    } else {
      _load();
    }
  }

  /// Disposes any loaded ad and resets the count.
  void reset() {
    _ad?.dispose();
    _ad = null;
    _loadedAt = null;
    _navigations = 0;
  }

  bool get _isReady {
    final ad = _ad;
    final loadedAt = _loadedAt;
    if (ad == null || loadedAt == null) return false;
    if (DateTime.now().difference(loadedAt) > maxAge) {
      AppLogger.warn('On-demand interstitial expired. Dropping it.');
      ad.dispose();
      _ad = null;
      _loadedAt = null;
      return false;
    }
    return true;
  }

  void _load() {
    if (_loading || _isReady) return;
    _loading = true;
    try {
      InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            AdStats.instance.interLoad.value++;
            ad.setImmersiveMode(true);
            _loading = false;
            _ad = ad;
            _loadedAt = DateTime.now();
          },
          onAdFailedToLoad: (error) {
            AdStats.instance.interFailed.value++;
            AppLogger.error('On-demand interstitial failed to load: $error');
            _loading = false;
          },
        ),
      );
    } catch (error) {
      AppLogger.error('On-demand interstitial load threw: $error');
      _loading = false;
    }
  }

  void _show() {
    final ad = _ad!;
    _ad = null;
    _loadedAt = null;
    _navigations = 0;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdImpression: (_) => AdStats.instance.interImp.value++,
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.error('On-demand interstitial failed to show: $error');
        ad.dispose();
        _showing = false;
      },
    );
    ad.show();
  }
}
