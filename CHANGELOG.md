## Unreleased

- **On-demand full-screen ads** (new, standalone classes -- existing preloading behavior is unchanged):
  - `OnDemandInterstitialAd`: an interstitial shown on every Nth navigation that starts loading one navigation earlier (the (N-1)th) instead of staying preloaded. If it is still loading when due it shows on the next navigation, and the following cycle loads/shows again on the same schedule.
  - `OnDemandRewardedInterstitialAd`: a rewarded interstitial requested only when needed (`load()` with a timeout, then `show(ad)`), with nothing preloaded or kept afterwards.
  - `OnDemandRewardedAd`: a rewarded video requested only when needed (`load()` with a timeout, then `show(ad)` which completes with whether the reward was earned); nothing preloaded or kept afterwards.
  - `OnDemandAppOpenAd`: an app open ad requested only when it should show (`loadAndShow()`, optionally on every return to the foreground via `startListening()`); shown only if it arrives within a timeout, never cached, never retried in the background.
  - Use them instead of the preloading formats by turning `AdFlag.showInterstitial` / `AdFlag.showRewardedInterstitial` (`showRewarded` for rewarded video, and `showOpenApp` + `showSplashAd` for app open) off.
  - All of them honor the master `AdFlag.showAd`.
- **Native retry limit** (opt-in): `AdConfigData.nativeRetryLimit`. A failed native ad load is retried that many times (one retry after 2 s for `1`), then the loader stops and waits for the next request, e.g. another screen asking for the ad. Left `null` (the default), the original indefinite backoff retry is unchanged.

## v1.0.7

- **Network Interruption & Auto-Recovery**:
  - Implemented continuous background auto-recovery retry (15s periodic cycle) when initial backoff retries are exhausted due to network loss.
  - Ads automatically recover and preload into memory as soon as network connectivity is restored without requiring manual re-initialization.
  - Added robust exception handling across all ad format catch blocks (`RewardAd`, `InterAd`, `RewardInterAd`, `AppOpenAdManager`, `LoadBannerAd`, `BaseNativeAdLoader`).
- **Rewarded Interstitial Format Integration**:
  - Added full preloading and management support for **Rewarded Interstitial Ads** via `RewardInterAd` and `showRewardedInterstitialAd(...)`.
- **Collapsible & Standard Banner Modularization**:
  - Introduced `ShowCollapsibleBannerAd` for dedicated, dynamic collapsible banner ad display.
  - Added strongly-typed `CollapsibleBannerPosition` enum (`bottom` and `top`) replacing string literals.
  - Added `FittedBox(fit: BoxFit.contain)` responsive layout container to scale standard and collapsible banners seamlessly inside parent constraints.
- **Native Customizer Live Updates**:
  - Fixed native ad disappearance on dynamic color selections by updating MethodChannel state without clearing active loaded ad instances.
  - Expanded `CustomNativeADStyle` to support title, body, button, tag foreground/background colors, radius sliders, and button gradient tokens.
  - Added optional `Key? key` parameter to `showNativeAd(...)` and `showCollapsibleBannerAd(...)` for instant subtree key identity updates.
- **Streamlined Library Exports**:
  - Exported all models, enums, constants, widgets, and singletons directly via `package:preload_google_ads/preload_google_ads.dart`.
- **Comprehensive Unit Testing Suite**:
  - Modularized unit tests into dedicated files under `test/`: `ad_commons_test.dart`, `banner_ad_test.dart`, `native_ad_test.dart`, `inter_ad_test.dart`, `rewarded_ad_test.dart`, `app_open_ad_test.dart`, and `preload_google_ads_test.dart`.
- **Showcase Example App Redesign**:
  - Streamlined navigation into clean top-level tabs: **Dashboard**, **Customizer**, **Native Feed**, **Banner Ads**, and **Ad Lab**.
  - Updated branding logo and app launcher icons across Android and iOS assets.

## v1.0.6

- Added Swift Package Manager (SPM) support for iOS.
- Improved package description for better pub.dev compliance and score.

## v1.0.5

- Added iOS implementation boilerplate and native ad factory foundations.
- General codebase cleanup and removal of unused constants.

## v1.0.4

- Modernized Android build configuration (Java 11, Kotlin 2.1.0, and latest AGP).
- Redesigned `README.md` for better clarity, aesthetics, and professional presentation.
- Organized project assets by moving demo GIFs to a dedicated `docs/assets` directory.

## v1.0.3

- Updated package version to `v1.0.3`.
- Fixed minor typos and wording issues across the codebase and documentation.
- No API changes or breaking behavior.
- Internal cleanups only; existing integrations continue to work without modification.

## v1.0.0

- Promoted to stable release from pre-release versions after multiple improvements and iterations.
- Consolidated and optimized internal architecture for long-term maintainability and scalability.
- Finalized and validated all major features:
    - Real-time ad status tracking across all supported ad types.
    - Stable and consistent ad lifecycle event handling (load, show, fail, click).
    - Custom native ad layout support with enhanced UI integration.
    - Full ad preloading for Open App, Interstitial, Rewarded, Native (Small/Medium), and Banner
      formats.
- Clean Dart analysis and fully production-ready for Android.
- Updated README.md with comprehensive usage samples and support documentation.
- Addressed minor bugs and preview issues from previous versions.
- Ready for production usage as v1.0.0 milestone.
