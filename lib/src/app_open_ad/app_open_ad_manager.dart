import '../ad_internal.dart';

/// Utility class that manages loading and showing app open ads.
class AppOpenAdManager extends BaseAdLoader {
  /// Singleton instance of [AppOpenAdManager].
  static final AppOpenAdManager instance = AppOpenAdManager._internal();

  /// Factory constructor providing access to the singleton [AppOpenAdManager].
  factory AppOpenAdManager() => instance;

  /// Private constructor for [AppOpenAdManager] singleton.
  AppOpenAdManager._internal();

  /// Enabled when either the resume-time app open ad or the cold-start
  /// splash ad is turned on -- both share the same preloaded ad instance.
  @override
  bool get isEnabled => shouldShowOpenAppAd || shouldShowSplashAd;

  @override
  String get adLabel => "App Open";

  @override
  void load() {
    loadAd();
  }

  /// The ad object to hold the loaded app open ad.
  AppOpenAd? _appOpenAd;

  /// Flag to track if an ad is currently being shown.
  bool get _isShowingAd => isShowing;

  /// Pending callback registered via [setSplashAdCallback], fired once the
  /// cold-start splash ad has been shown and dismissed, failed to show, or
  /// could not be obtained in time -- so the caller can navigate away from
  /// the splash screen.
  void Function(AppOpenAd? ad, AdError? error)? _splashAdCallback;

  /// Guards against showing the splash ad twice for the same registration.
  Timer? _splashTimeoutTimer;

  /// Maximum time to wait for the app open ad to finish loading before
  /// giving up on the splash ad and just invoking the callback, so the
  /// splash screen is never blocked indefinitely (e.g. no network).
  static const Duration _splashAdTimeout = Duration(seconds: 6);

  /// True once [armColdStartAutoShow] has been called for this process and
  /// the ad hasn't been auto-shown yet -- keeps the ad from being shown a
  /// second time on a later, unrelated load (e.g. the reload that follows
  /// a resume-time [showAdIfAvailable]).
  bool _armedForColdStartAutoShow = false;

  /// Arms automatic display of the app open ad the instant it finishes
  /// preloading, with no further calls from the host app required. Called
  /// once by [AdManager.initialize] when [AdFlag.showSplashAd] is enabled;
  /// a no-op otherwise. If a load is already in flight or the ad is
  /// already sitting loaded, this picks up on that rather than starting a
  /// redundant request.
  void armColdStartAutoShow() {
    if (!shouldShowSplashAd) return;

    _armedForColdStartAutoShow = true;

    if (isAdAvailable) {
      _showSplashAd();
    } else if (!isLoading) {
      loadAd();
    }
  }

  /// Registers [callback] to be invoked once the app open ad has been shown
  /// and dismissed on cold start. Fires immediately with `null` arguments
  /// if splash ads are disabled (see [AdFlag.showSplashAd]), or after
  /// [_splashAdTimeout] if no ad becomes available in time.
  void setSplashAdCallback(
    void Function(AppOpenAd? ad, AdError? error) callback,
  ) {
    if (!shouldShowSplashAd) {
      callback(null, null);
      return;
    }

    _splashAdCallback = callback;

    if (isAdAvailable) {
      _showSplashAd();
      return;
    }

    _splashTimeoutTimer = Timer(_splashAdTimeout, () {
      _finishSplash(null, null);
    });

    if (!isLoading) loadAd();
  }

  /// Shows the preloaded app open ad for the splash flow and resolves the
  /// pending [_splashAdCallback] once it is dismissed or fails to show.
  void _showSplashAd() {
    _splashTimeoutTimer?.cancel();
    _armedForColdStartAutoShow = false;

    if (!isAdAvailable || _isShowingAd) {
      _finishSplash(null, null);
      return;
    }

    state = AdLoadState.showing;

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        AppLogger.log('$ad onAdShowedFullScreenContent');
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.error('$ad onAdFailedToShowFullScreenContent: $error');
        ad.dispose();
        _appOpenAd = null;
        state = AdLoadState.failed;
        _finishSplash(null, error);
      },
      onAdImpression: (value) {
        AdStats.instance.openAppImp.value++;
      },
      onAdDismissedFullScreenContent: (ad) {
        AppLogger.log('$ad onAdDismissedFullScreenContent');
        ad.dispose();
        _appOpenAd = null;
        state = AdLoadState.initial;
        loadAd();
        _finishSplash(ad, null);
      },
    );

    _appOpenAd!.show();
  }

  /// Resolves and clears the pending splash callback, if any.
  void _finishSplash(AppOpenAd? ad, AdError? error) {
    _splashTimeoutTimer?.cancel();
    _splashTimeoutTimer = null;
    final callback = _splashAdCallback;
    _splashAdCallback = null;
    callback?.call(ad, error);
  }

  /// Load an [AppOpenAd].
  void loadAd() {
    if (!prepareLoad()) return;

    try {
      /// Attempt to load the App Open ad.
      AppOpenAd.load(
        adUnitId: unitIDAppOpen,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          /// Callback when the ad is successfully loaded.
          onAdLoaded: (ad) {
            AdStats.instance.openAppLoad.value++;
            _appOpenAd = ad;
            handleLoadSuccess();
            if (_splashAdCallback != null || _armedForColdStartAutoShow) {
              _showSplashAd();
            }
          },

          /// Callback if the ad fails to load.
          onAdFailedToLoad: (error) {
            AdStats.instance.openAppFailed.value++;
            _appOpenAd = null;
            handleFailureAndRetry(error, onRetry: () => loadAd());
            // Left armed/pending -- handleFailureAndRetry schedules another
            // load attempt, and a subsequent success should still trigger
            // the splash ad. Only a registered callback needs telling about
            // this particular failure so it isn't left hanging.
            if (_splashAdCallback != null) _finishSplash(null, error);
          },
        ),
      );
    } catch (error) {
      state = AdLoadState.failed;
      AppLogger.error('Exception during AppOpenAd load: $error');
      handleFailureAndRetry(error, onRetry: () => loadAd());
    }
  }

  /// Whether an ad is available to be shown.
  bool get isAdAvailable {
    return _appOpenAd != null && isAdLoaded;
  }

  /// Shows the ad, if one exists and is not already being shown.
  ///
  /// If the previously cached ad has expired, this just loads and caches a
  /// new ad.
  void showAdIfAvailable() {
    if (!isEnabled) return;

    /// Check if an ad is available, if not, load a new one.
    if (!isAdAvailable) {
      AppLogger.log('Tried to show ad before available.');
      loadAd();
      return;
    }

    /// Check if the ad is already being shown, if so, do nothing.
    if (_isShowingAd) {
      AppLogger.warn('Tried to show ad while already showing an ad.');
      return;
    }

    /// Check if the cached ad has expired based on the max cache duration.
    if (isExpired) {
      AppLogger.warn('Maximum cache duration exceeded. Loading another ad.');
      _appOpenAd!.dispose();
      _appOpenAd = null;
      loadTime = null;
      loadAd();
      return;
    }

    state = AdLoadState.showing;

    /// Set the callback to handle the ad's full-screen content events.
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      /// Callback when the ad is successfully shown.
      onAdShowedFullScreenContent: (ad) {
        AppLogger.log('$ad onAdShowedFullScreenContent');
      },

      /// Callback when the ad fails to show.
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.error('$ad onAdFailedToShowFullScreenContent: $error');
        ad.dispose();
        _appOpenAd = null;
        state = AdLoadState.failed;
      },

      /// Callback when the ad impression is logged.
      onAdImpression: (value) {
        AdStats.instance.openAppImp.value++;
      },

      /// Callback when the ad is dismissed.
      onAdDismissedFullScreenContent: (ad) {
        AppLogger.log('$ad onAdDismissedFullScreenContent');
        ad.dispose();
        _appOpenAd = null;
        state = AdLoadState.initial;
        loadAd();
      },
    );

    /// Show the app open ad.
    _appOpenAd!.show();
  }

  @override
  void reset() {
    _appOpenAd?.dispose();
    _appOpenAd = null;
    loadTime = null;
    _armedForColdStartAutoShow = false;
    _finishSplash(null, null);
    super.reset();
  }
}
