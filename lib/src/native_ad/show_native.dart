import '../ad_internal.dart';

/// A widget that determines which type of native ad (small or medium) to show
/// based on the `nativeADType` and the counter logic.
class ShowNative extends StatelessWidget {
  /// The type of native ad to display.
  final NativeADType nativeADType;

  /// Constructor for [ShowNative].
  const ShowNative({super.key, required this.nativeADType});

  @override
  Widget build(BuildContext context) {
    final isSmall = nativeADType == NativeADType.small;
    final loader =
        isSmall ? LoadSmallNative.instance : LoadMediumNative.instance;

    if (loader.counter >= getNativeCounter) {
      loader.resetCounter();
      if (shouldShowNativeAd) {
        // Show either small or medium native ad based on the `isSmall` flag.
        return isSmall ? const NativeSmall() : const MediumNative();
      } else {
        // If the native ad should not be shown, return an empty space.
        return const SizedBox.shrink();
      }
    } else {
      loader.incrementCounter();
      // If the counter limit is not reached, return an empty space.
      return const SizedBox.shrink();
    }
  }
}

/// A internal helper widget to manage common state for native ad views.
abstract class _NativeAdViewState<T extends StatefulWidget> extends State<T> {
  final BaseNativeAdLoader loader;
  final BoxConstraints constraints;
  NativeAd? _ad;

  /// True once a load attempt for this slot has come back empty-handed
  /// (and no queued ad has shown up since) -- collapses the slot instead
  /// of holding the placeholder open forever.
  bool _failed = false;

  _NativeAdViewState({required this.loader, required this.constraints});

  @override
  void initState() {
    super.initState();
    if (loader.ads.isNotEmpty) {
      // An ad was already sitting in the preload queue -- claim it
      // straight away, same as before.
      _ad = loader.ads.removeAt(0);
    } else {
      // Nothing ready yet: keep watching the shared loader's stats so
      // this slot can pick up an ad (or learn of a failure) the moment
      // one becomes available, instead of only checking once here in
      // initState and then never again.
      loader.loadStats.addListener(_onLoaderLoaded);
      loader.failedStats.addListener(_onLoaderFailed);
    }
    loader.loadAd();
  }

  /// Fires whenever *any* ad of this type finishes loading (this widget's
  /// own request or another slot's). Claims one for itself if it's still
  /// waiting and the queue actually has one on offer.
  void _onLoaderLoaded() {
    if (!mounted || _ad != null || loader.ads.isEmpty) return;
    setState(() {
      _ad = loader.ads.removeAt(0);
      _failed = false;
    });
    _stopWatchingLoader();
    // Claiming the just-landed ad leaves the shared queue empty again --
    // top it back up so the next slot/screen that asks doesn't have to
    // wait through a full load from scratch.
    loader.loadAd();
  }

  /// Fires whenever a load attempt for this ad type fails. Only collapses
  /// this slot if it's still waiting -- a retry that succeeds later (see
  /// [_onLoaderLoaded]) is free to un-collapse it while still mounted.
  void _onLoaderFailed() {
    if (!mounted || _ad != null) return;
    setState(() => _failed = true);
  }

  void _stopWatchingLoader() {
    loader.loadStats.removeListener(_onLoaderLoaded);
    loader.failedStats.removeListener(_onLoaderFailed);
  }

  @override
  void dispose() {
    _stopWatchingLoader();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ad == null) {
      // Still waiting on a load: hold the slot open at the ad's own size
      // instead of collapsing it, so surrounding content doesn't jump
      // once the ad actually lands. Only collapse once a load attempt has
      // actually come back empty.
      return _failed
          ? const SizedBox.shrink()
          : _buildShell(
              context,
              child: _NativeAdShimmerPlaceholder(
                isDark: NativeADStyle.instance.isDarkMode(context: context),
              ),
            );
    }

    try {
      return _buildShell(context, child: Center(child: AdWidget(ad: _ad!)));
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  /// The same sized/decorated container used for both the loading
  /// placeholder and the real ad, so swapping between them never changes
  /// the slot's footprint.
  Widget _buildShell(BuildContext context, {required Widget child}) {
    final isDark = NativeADStyle.instance.isDarkMode(context: context);
    final decoration = (isDark && NativeADStyle.instance.darkDecoration != null)
        ? NativeADStyle.instance.darkDecoration
        : NativeADStyle.instance.lightDecoration;

    return Container(
      decoration: decoration,
      constraints: constraints,
      margin: NativeADStyle.instance.margin,
      padding: NativeADStyle.instance.padding,
      child: child,
    );
  }
}

/// A skeleton of a native ad -- icon block, headline/body lines, and a CTA
/// button block -- swept by an animated shimmer highlight, shown inside the
/// ad shell while a native ad is still loading.
class _NativeAdShimmerPlaceholder extends StatefulWidget {
  final bool isDark;

  const _NativeAdShimmerPlaceholder({required this.isDark});

  @override
  State<_NativeAdShimmerPlaceholder> createState() =>
      _NativeAdShimmerPlaceholderState();
}

class _NativeAdShimmerPlaceholderState
    extends State<_NativeAdShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isDark
        ? const Color(0xFF505058) // 46464E + 10
        : const Color(0xFFFEFEFF); // F4F4F6 + 10
    final highlightColor = widget.isDark
        ? const Color(0xFF3C3C44) // 46464E - 10
        : const Color(0xFFEAEAEC); // F4F4F6 - 10

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.15, 0.5, 0.85],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 150;
          final iconSize = compact ? 40.0 : 56.0;

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBlock(width: iconSize, height: iconSize, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shimmerBlock(width: double.infinity, height: 12),
                      const SizedBox(height: 8),
                      _shimmerBlock(width: 90, height: 10),
                      if (!compact) ...[
                        const SizedBox(height: 16),
                        _shimmerBlock(width: double.infinity, height: 9),
                        const SizedBox(height: 6),
                        _shimmerBlock(width: double.infinity, height: 9),
                        const SizedBox(height: 6),
                        _shimmerBlock(width: 140, height: 9),
                        const SizedBox(height: 16),
                        _shimmerBlock(width: 96, height: 26, radius: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _shimmerBlock({
    required double width,
    required double height,
    double radius = 4,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Solid + opaque -- the visible color comes entirely from the
        // ShaderMask gradient above via BlendMode.srcATop.
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Translates the shimmer gradient horizontally across the placeholder's
/// bounds as [slidePercent] sweeps 0..1, so the highlight glides fully
/// off-screen to fully off-screen on the other side each animation cycle.
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (2 * slidePercent - 1),
      0.0,
      0.0,
    );
  }
}

/// A widget that displays a medium-sized native ad.
class MediumNative extends StatefulWidget {
  /// Constructor for [MediumNative].
  const MediumNative({super.key});

  @override
  State<MediumNative> createState() => _MediumNativeState();
}

class _MediumNativeState extends _NativeAdViewState<MediumNative> {
  _MediumNativeState()
      : super(
          loader: LoadMediumNative.instance,
          constraints: NativeADStyle.instance.mediumConstraintsSize,
        );
}

/// A widget that displays a small-sized native ad.
class NativeSmall extends StatefulWidget {
  /// Constructor for [NativeSmall].
  const NativeSmall({super.key});

  @override
  State<NativeSmall> createState() => _NativeSmallState();
}

class _NativeSmallState extends _NativeAdViewState<NativeSmall> {
  _NativeSmallState()
      : super(
          loader: LoadSmallNative.instance,
          constraints: NativeADStyle.instance.smallConstraintsSize,
        );
}
