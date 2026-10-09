import '../ad_internal.dart';

/// An app open ad that is **requested at the moment it should be shown** --
/// nothing is preloaded, and a failed request is never retried in the
/// background.
///
/// [loadAndShow] requests a fresh ad and shows it only if it arrives within
/// [loadTimeout], because an app open ad popping up after the user has
/// already started using the app is worse than no ad. An ad that turns up
/// later isn't thrown away, though: it is kept (for up to [maxAge]) and shown
/// straight away by the next [loadAndShow] -- typically the next return from
/// the background -- instead of making a new request. Call it once on a cold
/// start, and use [startListening] to call it on every return from the
/// background:
///
/// ```dart
/// final appOpen = OnDemandAppOpenAd(adUnitId: 'ca-app-pub-.../...');
/// await appOpen.loadAndShow();   // cold start
/// appOpen.startListening();      // every later resume
/// ```
///
/// This is a standalone class: it does not touch [AppOpenAdManager],
/// [LifeCycleManager] or the [AdFlag.showOpenApp] / [AdFlag.showSplashAd]
/// toggles, so it can be used instead of the preloading app open ad (turn
/// that one off with both of those flags set to false). The one switch it does
/// honor is the master [AdFlag.showAd]: while that is off it makes no request
/// and shows nothing.
class OnDemandAppOpenAd {
  /// The AdMob ad unit id requested for every load.
  final String adUnitId;

  /// How long [loadAndShow] waits for the ad before giving up.
  final Duration loadTimeout;

  /// Creates a controller for [adUnitId]. [loadAndShow] gives up after
  /// [loadTimeout].
  OnDemandAppOpenAd({
    required this.adUnitId,
    this.loadTimeout = const Duration(seconds: 4),
  });

  /// How long an ad that arrived too late is kept for the next
  /// [loadAndShow]. Kept well inside AdMob's 4-hour limit for app open ads.
  static const Duration maxAge = Duration(hours: 3);

  bool _busy = false;
  StreamSubscription<AppState>? _appStateSub;

  /// An ad that loaded after its [loadAndShow] had already given up, and when
  /// it loaded -- shown by the next [loadAndShow] instead of a new request.
  AppOpenAd? _lateAd;
  DateTime? _lateAdLoadedAt;

  /// Whether a request or a showing ad is in progress right now. While this
  /// is true, further [loadAndShow] calls do nothing.
  bool get isBusy => _busy;

  /// Whether this controller is currently reacting to app foreground events.
  bool get isListening => _appStateSub != null;

  /// Requests an app open ad and shows it if it arrives within [loadTimeout]
  /// -- or, if an earlier request's ad arrived too late and is still fresh,
  /// shows that one right away without a new request.
  ///
  /// Completes with `true` once the ad has been shown and dismissed, and with
  /// `false` if nothing was shown -- ads are off, another call is still in
  /// progress, the request failed or timed out, or the ad failed to show.
  /// [timeout] overrides [loadTimeout] for this call only (e.g. a longer wait
  /// on a cold start).
  Future<bool> loadAndShow({Duration? timeout}) async {
    if (!shouldShowAd || _busy) return false;
    _busy = true;
    try {
      final late = _takeLateAd();
      if (late != null) return await _show(late);
      final ad = await _load(timeout ?? loadTimeout);
      if (ad == null) return false;
      return await _show(ad);
    } finally {
      _busy = false;
    }
  }

  /// Starts calling [loadAndShow] every time the app comes back to the
  /// foreground. Safe to call more than once.
  void startListening() {
    if (_appStateSub != null) return;
    AppStateEventNotifier.startListening();
    _appStateSub = AppStateEventNotifier.appStateStream.listen((state) {
      if (state == AppState.foreground) loadAndShow();
    });
  }

  /// Stops reacting to foreground events.
  void stopListening() {
    _appStateSub?.cancel();
    _appStateSub = null;
  }

  Future<AppOpenAd?> _load(Duration timeout) {
    final completer = Completer<AppOpenAd?>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        AppLogger.warn('On-demand app open ad timed out.');
        completer.complete(null);
      }
    });
    try {
      AdStats.instance.openAppReq.value++;
      AppOpenAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            AdStats.instance.recordLoadSource(ad);
            timer.cancel();
            AdStats.instance.openAppLoad.value++;
            if (completer.isCompleted) {
              // Arrived after loadAndShow gave up: keep it for the next one
              // rather than wasting the load.
              _storeLateAd(ad);
            } else {
              completer.complete(ad);
            }
          },
          onAdFailedToLoad: (error) {
            timer.cancel();
            AdStats.instance.openAppFailed.value++;
            AppLogger.error('On-demand app open ad failed to load: $error');
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (error) {
      timer.cancel();
      AppLogger.error('On-demand app open ad load threw: $error');
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  void _storeLateAd(AppOpenAd ad) {
    if (_lateAd != null) {
      ad.dispose();
      return;
    }
    AppLogger.log('On-demand app open ad arrived late; kept for next time.');
    _lateAd = ad;
    _lateAdLoadedAt = DateTime.now();
  }

  /// The kept late ad if it's still within [maxAge] (dropping it otherwise),
  /// handing over ownership -- it's cleared either way.
  AppOpenAd? _takeLateAd() {
    final ad = _lateAd;
    final loadedAt = _lateAdLoadedAt;
    _lateAd = null;
    _lateAdLoadedAt = null;
    if (ad == null || loadedAt == null) return null;
    if (DateTime.now().difference(loadedAt) > maxAge) {
      ad.dispose();
      return null;
    }
    return ad;
  }

  Future<bool> _show(AppOpenAd ad) {
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdImpression: (_) => AdStats.instance.openAppImp.value++,
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.error('On-demand app open ad failed to show: $error');
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    ad.show();
    return done.future;
  }
}
