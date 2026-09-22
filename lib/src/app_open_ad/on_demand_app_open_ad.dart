import '../ad_internal.dart';

/// An app open ad that is **requested at the moment it should be shown** --
/// nothing is preloaded, nothing is cached, and a failed request is never
/// retried in the background.
///
/// [loadAndShow] requests a fresh ad and shows it only if it arrives within
/// [loadTimeout]; an ad that turns up later is thrown away, because an app
/// open ad appearing after the user has already started using the app is
/// worse than no ad. Call it once on a cold start, and use
/// [startListening] to call it on every return from the background:
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

  bool _busy = false;
  StreamSubscription<AppState>? _appStateSub;

  /// Whether a request or a showing ad is in progress right now. While this
  /// is true, further [loadAndShow] calls do nothing.
  bool get isBusy => _busy;

  /// Whether this controller is currently reacting to app foreground events.
  bool get isListening => _appStateSub != null;

  /// Requests an app open ad and shows it if it arrives within [loadTimeout].
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
            timer.cancel();
            AdStats.instance.openAppLoad.value++;
            if (completer.isCompleted) {
              ad.dispose();
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
