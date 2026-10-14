import 'package:flutter/scheduler.dart' show SchedulerPhase;

import '../ad_internal.dart';

/// Base class for loading native ads to reduce code duplication.
abstract class BaseNativeAdLoader extends BaseAdLoader {
  /// List to store the loaded native ads.
  List<NativeAd> ads = [];

  /// Failed native loads so far this session, small and medium combined --
  /// static so both loaders share it, and never cleared by [reset] (which
  /// reloadNativeAd calls), only by a new app process.
  static int _sessionFailures = 0;

  /// Whether [AdConfigData.nativeMaxFailuresPerSession] has been hit, which
  /// switches native off for the rest of the session. Always `false` while
  /// the cap is disabled.
  static bool get failureLimitReached {
    final max = nativeMaxFailuresPerSession;
    return max != null && _sessionFailures >= max;
  }

  @override
  bool get isEnabled => shouldShowNativeAd && !failureLimitReached;

  @override
  String get adLabel => adTypeLabel;

  @override
  int? get maxRetriesPerRequest => nativeRetryLimit;

  @override
  void load() {
    loadAd();
  }

  /// Abstract getters for ad-specific configuration.
  /// The factory ID to use for this ad loader.
  String? get factoryId;

  /// The template style to use for this ad loader.
  NativeTemplateStyle? get templateStyle;

  /// The stats for requests sent to Google.
  ValueNotifier<int> get reqStats;

  /// The stats for loaded ads.
  ValueNotifier<int> get loadStats;

  /// The stats for ad impressions.
  ValueNotifier<int> get impStats;

  /// The stats for failed ad loads.
  ValueNotifier<int> get failedStats;

  /// The human-readable label for this ad type.
  String get adTypeLabel;

  /// Loads a native ad.
  Future<void> loadAd() async {
    // A load bumps ValueNotifiers (reqStats, and loadStats/failedStats via
    // its callbacks) that widgets listen to -- the Ad Metrics Lab, native ad
    // slots. Called while a frame is being built (e.g. from a native ad
    // slot's initState), that marks those widgets dirty mid-build and throws
    // "setState() or markNeedsBuild() called during build", so wait for the
    // frame to finish instead.
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => loadAd());
      return;
    }
    if (ads.isNotEmpty || !prepareLoad()) return;
    // A request made while an automatic retry is still pending (e.g. another
    // screen asking for the ad) simply takes the retry's place.
    if (maxRetriesPerRequest != null) cancelReloadTimer();

    try {
      reqStats.value++;
      NativeAd? nativeAd;
      nativeAd = NativeAd(
        factoryId: factoryId,
        adUnitId: unitIDNative,
        nativeTemplateStyle: templateStyle,
        listener: NativeAdListener(
          onAdLoaded: (ad) async {
            AdStats.instance.recordLoadSource(ad);
            if (nativeAd != null) {
              ads.add(nativeAd);
            }
            // handleLoadSuccess() must run before the loadStats bump --
            // ValueNotifier listeners (e.g. a native ad slot claiming this
            // ad and immediately requesting the next one) fire synchronously
            // off that increment, and need to see state already flipped to
            // AdLoadState.ready rather than still AdLoadState.loading, or
            // their reload gets rejected by prepareLoad()'s isLoading check.
            handleLoadSuccess();
            loadStats.value++;
          },
          onAdImpression: (ad) {
            impStats.value++;
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            // Before the failedStats bump, so slots reacting to it already
            // see the cap (state) -- same ordering reason as onAdLoaded.
            _onLoadFailed(error);
            failedStats.value++;
          },
        ),
        request: const AdRequest(),
      );
      await nativeAd.load();
    } catch (error) {
      state = AdLoadState.failed;
      AppLogger.error("Error in $adTypeLabel ad load catch: $error");
      _onLoadFailed(error);
    }
  }

  /// Counts the failure toward the session cap, then retries as usual --
  /// unless that was the failure that hit the cap, in which case no retry is
  /// scheduled and any pending one is dropped.
  void _onLoadFailed(Object error) {
    _sessionFailures++;
    if (failureLimitReached) {
      handleLoadError(adLabel, error);
      cancelReloadTimer();
      AppLogger.log(
        "Native ads stopped for this session after $_sessionFailures "
        "failed loads (nativeMaxFailuresPerSession).",
      );
      return;
    }
    handleFailureAndRetry(error, onRetry: () => loadAd());
  }

  /// Disposes of all loaded ads and resets the state.
  @override
  void reset() {
    for (final ad in ads) {
      ad.dispose();
    }
    ads.clear();
    super.reset();
  }
}

///==============================================================================
///   ** Medium Native ***
///==============================================================================

/// A singleton class that loads medium native ads.
class LoadMediumNative extends BaseNativeAdLoader {
  /// Singleton instance of [LoadMediumNative].
  static final LoadMediumNative instance = LoadMediumNative._internal();

  /// Factory constructor to provide access to the singleton [LoadMediumNative].
  factory LoadMediumNative() => instance;

  /// Private constructor for [LoadMediumNative] singleton.
  LoadMediumNative._internal();

  @override
  String? get factoryId => NativeADStyle.instance.mediumNativeFactoryId;

  @override
  NativeTemplateStyle? get templateStyle =>
      NativeADStyle.instance.nativeMediumTemplateStyle;

  /// Statistics for medium native ad requests.
  @override
  ValueNotifier<int> get reqStats => AdStats.instance.nativeReqM;

  /// Statistics for medium native ad loads.
  @override
  ValueNotifier<int> get loadStats => AdStats.instance.nativeLoadM;

  /// Statistics for medium native ad impressions.
  @override
  ValueNotifier<int> get impStats => AdStats.instance.nativeImpM;

  /// Statistics for medium native ad load failures.
  @override
  ValueNotifier<int> get failedStats => AdStats.instance.nativeFailedM;
  @override
  String get adTypeLabel => "Medium Native";

  /// Compatibility getter for existing code to access medium native ads.
  List<NativeAd> get nativeObjectLarge => ads;
}

///==============================================================================
///   ** Small Native ***
///==============================================================================

/// A singleton class that loads small native ads.
class LoadSmallNative extends BaseNativeAdLoader {
  /// Singleton instance of [LoadSmallNative].
  static final LoadSmallNative instance = LoadSmallNative._internal();

  /// Factory constructor to provide access to the singleton [LoadSmallNative].
  factory LoadSmallNative() => instance;

  /// Private constructor for [LoadSmallNative] singleton.
  LoadSmallNative._internal();

  @override
  String? get factoryId => NativeADStyle.instance.smallNativeFactoryId;

  @override
  NativeTemplateStyle? get templateStyle =>
      NativeADStyle.instance.nativeSmallTemplateStyle;

  /// Statistics for small native ad requests.
  @override
  ValueNotifier<int> get reqStats => AdStats.instance.nativeReqS;

  /// Statistics for small native ad loads.
  @override
  ValueNotifier<int> get loadStats => AdStats.instance.nativeLoadS;

  /// Statistics for small native ad impressions.
  @override
  ValueNotifier<int> get impStats => AdStats.instance.nativeImpS;

  /// Statistics for small native ad load failures.
  @override
  ValueNotifier<int> get failedStats => AdStats.instance.nativeFailedS;

  /// Label for small native ads.
  @override
  String get adTypeLabel => "Small Native";

  /// Compatibility getter for existing code to access small native ads.
  List<NativeAd> get nativeObjectSmall => ads;
}
