import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'utils.dart';

// Enum for breakpoint names for type safety.
enum BreakpointName {
  mobile,
  tablet,
  desktop,
  laptop,
  wide,
  unknown,
  mobileCard,
  tabletCard,
  desktopCard,
  tooNarrow,
}

/// Enum for responsive image scaling.
enum ImageScale { s, m, l }

/// Represents a range of screen widths for responsive design.
@immutable
class Breakpoint {
  /// The starting width (inclusive) for this breakpoint.
  final double start;

  /// The ending width (inclusive) for this breakpoint.
  final double end;

  /// The enum name identifying the breakpoint. Defaults to [BreakpointName.unknown].
  final BreakpointName name;

  /// Creates a breakpoint definition.
  const Breakpoint({
    required this.start,
    required this.end,
    this.name = BreakpointName.unknown,
  })  : assert(start >= 0, 'Breakpoint start must be non-negative.'),
        assert(
          end >= start,
          'Breakpoint end must be greater than or equal to start.',
        );

  /// Creates a copy of this Breakpoint but with the given fields replaced with the new values.
  Breakpoint copyWith({double? start, double? end, BreakpointName? name}) =>
      Breakpoint(
        start: start ?? this.start,
        end: end ?? this.end,
        name: name ?? this.name,
      );

  @override
  String toString() =>
      'Breakpoint(start: $start, end: $end, name: ${name.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Breakpoint &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          name == other.name;

  @override
  int get hashCode => Object.hash(start, end, name);
}

typedef ThemeBuilderFn = ThemeData Function(ResponsiveFrameworkData);

/// A StatefulWidget that provides responsive breakpoint information and scaling factors to its descendants.
///
/// It determines the current breakpoint based on screen width, calculates scaling factors
/// (based on device pixel ratio and text scaling settings), and applies a scaled [TextTheme].
/// Access data via `ResponsiveFramework.of(context)` or the convenient `context.responsive`.
class ResponsiveFramework extends StatefulWidget {
  final Widget child;

  /// A list of [Breakpoint] definitions used to determine responsiveness.
  final List<Breakpoint> breakpoints;

  /// Calculate responsiveness based on the shortest
  /// side of the screen, instead of the width.
  ///
  /// This is useful for ensuring layout consistency regardless of orientation.
  /// When true, `screenWidth` in [ResponsiveFrameworkData] will be the shorter side,
  /// and `screenHeight` will be the longer side.
  final bool useShortestSide;
  final ThemeBuilderFn themeBuilder;

  /// A wrapper widget that makes child widgets responsive and applies scaling.
  const ResponsiveFramework({
    super.key,
    required this.child,
    required this.breakpoints,
    required this.themeBuilder,
    this.useShortestSide = false,
  }) : assert(
          breakpoints.length > 0,
          'At least one breakpoint must be provided.',
        );

  @override
  ResponsiveFrameworkState createState() => ResponsiveFrameworkState();

  /// A convenience builder method for wrapping the app.
  static Widget builder({
    required Widget child,
    required List<Breakpoint> breakpoints,
    required ThemeBuilderFn themeBuilder,
    bool useShortestSide = false,
  }) {
    return ResponsiveFramework(
      breakpoints: breakpoints,
      useShortestSide: useShortestSide,
      themeBuilder: themeBuilder,
      child: child,
    );
  }

  /// The data from the closest instance of this class that encloses the given context.
  ///
  /// Throws a [FlutterError] if no [ResponsiveFramework] ancestor is found.
  /// Consider using the `context.responsive` extension getter for more concise access.
  static ResponsiveFrameworkData of(BuildContext context) {
    final InheritedResponsiveFramework? data = context
        .dependOnInheritedWidgetOfExactType<InheritedResponsiveFramework>();
    if (data != null) return data.data;
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary(
        'ResponsiveFramework.of() called with a context that does not contain a ResponsiveFramework.',
      ),
      ErrorDescription(
        'No ResponsiveFramework ancestor could be found starting from the context that was passed '
        'to ResponsiveFramework.of(). Place a ResponsiveFramework widget at the root of the app '
        'or supply a ResponsiveFramework.builder.',
      ),
      context.describeElement('The context used was'),
    ]);
  }
}

/// The logic and internal state for the [ResponsiveFramework] widget.
class ResponsiveFrameworkState extends State<ResponsiveFramework>
    with WidgetsBindingObserver {
  // Current derived values (exposed via ResponsiveFrameworkData)
  double _derivedScreenWidth = 0;
  double _derivedScreenHeight = 0;
  Breakpoint _derivedBreakpoint = const Breakpoint(start: 0, end: 0);
  double _derivedBaseScaleFactor = 1.0;
  double _derivedEffectiveTextScaleFactor = 1.0;
  Orientation _derivedOrientation = Orientation.portrait;
  double _derivedCurrentTextScale = 1.0;

  List<Breakpoint> _sortedBreakpoints = [];
  final _logger = useLogger('RFWK'); // Logger for ResponsiveFramework

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateAndSortBreakpoints();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recalculateAndNotifyIfChanged(debugReason: "initState");
      }
    });
  }

  @override
  void didUpdateWidget(ResponsiveFramework oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool breakpointsChanged =
        !listEquals(widget.breakpoints, oldWidget.breakpoints);
    if (breakpointsChanged ||
        widget.useShortestSide != oldWidget.useShortestSide) {
      if (breakpointsChanged) {
        _updateAndSortBreakpoints();
      }
      _recalculateAndNotifyIfChanged(debugReason: "didUpdateWidget");
    }
  }

  void _updateAndSortBreakpoints() {
    _sortedBreakpoints = List.from(widget.breakpoints);
    _sortedBreakpoints.sort(ResponsiveUtils.breakpointComparator);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This is called when an InheritedWidget that this widget depends on changes.
    // This includes MediaQuery.
    _recalculateAndNotifyIfChanged(debugReason: "didChangeDependencies");
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // This is called when window metrics change (size, text scale, etc.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recalculateAndNotifyIfChanged(debugReason: "didChangeMetrics");
      }
    });
  }

  /// Recalculates all derived metrics and calls setState only if significant values changed.
  void _recalculateAndNotifyIfChanged({required String debugReason}) {
    // Store old derived values before recalculation
    final oldScreenWidth = _derivedScreenWidth;
    final oldScreenHeight = _derivedScreenHeight;
    final oldBreakpointName = _derivedBreakpoint.name;
    final oldBaseScaleFactor = _derivedBaseScaleFactor;
    final oldEffectiveTextScaleFactor = _derivedEffectiveTextScaleFactor;
    final oldOrientation = _derivedOrientation;
    final oldCurrentTextScale = _derivedCurrentTextScale;

    // --- Read current raw MediaQuery values ---
    final currentWindowSize = MediaQuery.sizeOf(context);
    // Reverting to your original textScaleFactor usage as requested
    // ignore: deprecated_member_use
    final currentTextScaleFactor = MediaQuery.of(context).textScaleFactor;
    final currentDevicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // --- Recalculate derived values ---
    final physicalWidth = widget.useShortestSide
        ? min(currentWindowSize.width, currentWindowSize.height)
        : currentWindowSize.width;
    final physicalHeight = widget.useShortestSide
        ? max(currentWindowSize.width, currentWindowSize.height)
        : currentWindowSize.height;

    _derivedScreenWidth =
        ResponsiveUtils.calculateReducedScreenWidthByTextScaler(
      originalWidth: physicalWidth,
      textScalerFactor:
          currentTextScaleFactor, // Using the double factor directly
    );
    _derivedScreenHeight = physicalHeight;

    _derivedOrientation = (currentWindowSize.width > currentWindowSize.height)
        ? Orientation.landscape
        : Orientation.portrait;

    _derivedBreakpoint = _sortedBreakpoints.firstWhereOrNull(
          (bp) =>
              _derivedScreenWidth >= bp.start && _derivedScreenWidth <= bp.end,
        ) ??
        (_sortedBreakpoints.isNotEmpty
            ? _sortedBreakpoints.first
            : const Breakpoint(start: 0, end: 0));

    _derivedBaseScaleFactor = currentDevicePixelRatio;
    _derivedEffectiveTextScaleFactor =
        _derivedBaseScaleFactor * currentTextScaleFactor;
    _derivedCurrentTextScale = currentTextScaleFactor;

    // --- Compare new derived values with previously stored derived values ---
    bool significantChange = _derivedScreenWidth != oldScreenWidth ||
        _derivedScreenHeight != oldScreenHeight ||
        _derivedBreakpoint.name != oldBreakpointName ||
        _derivedBaseScaleFactor != oldBaseScaleFactor ||
        _derivedEffectiveTextScaleFactor != oldEffectiveTextScaleFactor ||
        _derivedOrientation != oldOrientation ||
        _derivedCurrentTextScale != oldCurrentTextScale;

    // Log the comparison for diagnostics
    if (significantChange) {
      _logger.verbose(
        "Significant change detected from '$debugReason', triggering setState. Differences:",
      );
      if (_derivedScreenWidth != oldScreenWidth) {
        _logger.verbose(
          "  screenWidth: $oldScreenWidth -> $_derivedScreenWidth",
        );
      }
      if (_derivedScreenHeight != oldScreenHeight) {
        _logger.verbose(
          "  screenHeight: $oldScreenHeight -> $_derivedScreenHeight",
        );
      }
      if (_derivedBreakpoint.name != oldBreakpointName) {
        _logger.verbose(
          "  breakpointName: $oldBreakpointName -> ${_derivedBreakpoint.name}",
        );
      }
      if (_derivedBaseScaleFactor != oldBaseScaleFactor) {
        _logger.verbose(
          "  baseScaleFactor: $oldBaseScaleFactor -> $_derivedBaseScaleFactor",
        );
      }
      if (_derivedEffectiveTextScaleFactor != oldEffectiveTextScaleFactor) {
        _logger.verbose(
          "  effectiveTextScaleFactor: $oldEffectiveTextScaleFactor -> $_derivedEffectiveTextScaleFactor",
        );
      }
      if (_derivedOrientation != oldOrientation) {
        _logger.verbose(
          "  orientation: $oldOrientation -> $_derivedOrientation",
        );
      }
      if (_derivedCurrentTextScale != oldCurrentTextScale) {
        _logger.verbose(
          "  currentTextScale: $oldCurrentTextScale -> $_derivedCurrentTextScale",
        );
      }
    }
    if (significantChange) {
      if (mounted) {
        setState(() {
          // The act of calling setState will trigger a rebuild,
          // and the build method will use the new _derived values.
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The _derivedValues are updated by lifecycle methods (_recalculateAndNotifyIfChanged)
    // So, here we construct ResponsiveFrameworkData with the latest _derivedValues.

    final frameworkData = ResponsiveFrameworkData(
      screenWidth: _derivedScreenWidth,
      screenHeight: _derivedScreenHeight,
      breakpoint: _derivedBreakpoint,
      breakpoints: List.unmodifiable(
        _sortedBreakpoints,
      ), // Pass sorted and unmodifiable list
      isMobile: _derivedBreakpoint.name == BreakpointName.mobile,
      isTablet: _derivedBreakpoint.name == BreakpointName.tablet,
      isLaptop: _derivedBreakpoint.name == BreakpointName.laptop,
      isDesktop: _derivedBreakpoint.name == BreakpointName.desktop,
      isWide: _derivedBreakpoint.name == BreakpointName.wide,
      orientation: _derivedOrientation,
      baseScaleFactor: _derivedBaseScaleFactor,
      effectiveTextScaleFactor: _derivedEffectiveTextScaleFactor,
      currentTextScale: _derivedCurrentTextScale,
    );

    final scaledSizeTheme = widget.themeBuilder(frameworkData);
    _logger.debug(
      'Rebuilding theme. Scale Factor: ${_derivedBaseScaleFactor * _derivedCurrentTextScale}',
    );

    // Using your original textScaleFactor approach for createScaledTextTheme
    final currentTextScaleFactor = _derivedCurrentTextScale;
    final scaledTextTheme = ResponsiveUtils.createScaledTextTheme(
      originalTextTheme: scaledSizeTheme.textTheme,
      effectiveScaleFactor: _derivedBaseScaleFactor * currentTextScaleFactor,
    );
    final scaledTheme = scaledSizeTheme.copyWith(textTheme: scaledTextTheme);

    return InheritedResponsiveFramework(
      data: frameworkData,
      child: Theme(data: scaledTheme, child: widget.child),
    );
  }
}

@immutable
class ResponsiveFrameworkData {
  final double screenWidth;
  final double screenHeight;
  final Breakpoint breakpoint;
  final List<Breakpoint> breakpoints;
  final bool isMobile;
  final bool isTablet;
  final bool isLaptop;
  final bool isDesktop;
  final bool isWide;
  final Orientation orientation;
  final double baseScaleFactor;
  final double effectiveTextScaleFactor;
  final double currentTextScale;

  late final Map<double, double> _adaptSizeCache = {};
  late final Map<double, double> _adaptFontSizeCache = {};

  ResponsiveFrameworkData({
    required this.screenWidth,
    required this.screenHeight,
    required this.breakpoint,
    required this.breakpoints,
    required this.isMobile,
    required this.isTablet,
    required this.isLaptop,
    required this.isDesktop,
    required this.isWide,
    required this.orientation,
    required this.baseScaleFactor,
    required this.effectiveTextScaleFactor,
    required this.currentTextScale,
  });

  @override
  String toString() {
    return 'ResponsiveFrameworkData(screenWidth: $screenWidth, screenHeight: $screenHeight, breakpoint: $breakpoint, orientation: $orientation, effectiveTextScaleFactor: $effectiveTextScaleFactor, currentTextScale: $currentTextScale)';
  }

  bool equals(BreakpointName name) => breakpoint.name == name;

  bool largerThan(BreakpointName name, {double? width}) {
    final bp = breakpoints.firstWhereOrNull((element) => element.name == name);
    if (bp == null || bp.end == double.infinity) return false;
    return (width ?? screenWidth) > bp.end;
  }

  bool largerOrEqualTo(BreakpointName name, {double? width}) {
    final bp = breakpoints.firstWhereOrNull((element) => element.name == name);
    if (bp == null) return false;
    return (width ?? screenWidth) >= bp.start;
  }

  bool smallerThan(BreakpointName name, {double? width}) {
    final bp = breakpoints.firstWhereOrNull((element) => element.name == name);
    if (bp == null) return false;
    return (width ?? screenWidth) < bp.start;
  }

  bool smallerOrEqualTo(BreakpointName name, {double? width}) {
    final bp = breakpoints.firstWhereOrNull((element) => element.name == name);
    if (bp == null) return false;
    if (bp.end == double.infinity) return true;
    return (width ?? screenWidth) <= bp.end;
  }

  bool between(BreakpointName startName, BreakpointName endName) {
    final startBp = breakpoints.firstWhereOrNull((e) => e.name == startName);
    final endBp = breakpoints.firstWhereOrNull((e) => e.name == endName);
    if (startBp == null || endBp == null) return false;
    final effectiveStart = min(startBp.start, endBp.start);
    final effectiveEnd = max(startBp.end, endBp.end);
    return screenWidth >= effectiveStart && screenWidth <= effectiveEnd;
  }

  double adaptSize(double targetSize) {
    return _adaptSizeCache.putIfAbsent(targetSize, () {
      return ResponsiveUtils.calculatePreScaledLogicalSize(
        targetLogicalSize: targetSize,
        scaleFactor: baseScaleFactor,
      );
    });
  }

  double adaptFontSize(double targetSize) {
    return _adaptFontSizeCache.putIfAbsent(targetSize, () {
      return ResponsiveUtils.calculatePreScaledFontSize(
        targetSize: targetSize,
        scaleFactor: effectiveTextScaleFactor,
      );
    });
  }

  /// Calculates a scaled size based on a base scale factor and the original size.
  ///
  /// The scaling logic is: 2 to the power of (min(2, baseScaleFactor.ceil() - 1)).
  /// This effectively scales by 1x, 2x, or 4x.
  ///
  /// A 128 width will remain 128px for DPR 1.0 (most desktop browser)
  /// A 128 width will become 256px for DPR 1.0 > x < 2.0 (Tablet, low/mid tier mobile)
  /// A 128 width will become 512px for DPR 2.0 > x  (high end display)
  double scaleToDevicePixelRatio(double originalSize) {
    final int exponent = (baseScaleFactor.ceil() - 1).clamp(0, 2).toInt();
    final int multiplier = 1 << exponent;
    return multiplier * originalSize;
  }

  /// Determines which image scale (s, m, l) to use based on device pixel ratio.
  ///
  /// This helps in selecting the most appropriate image asset from a set of sizes (e.g., img-s, img-m, img-l).
  /// The logic mirrors `scaleToDevicePixelRatio`:
  /// - DPR <= 1.0 maps to [ImageScale.s].
  /// - DPR > 1.0 and <= 2.0 maps to [ImageScale.m].
  /// - DPR > 2.0 maps to [ImageScale.l].
  ImageScale getImageScaleForDevice() {
    final int exponent = (baseScaleFactor.ceil() - 1).clamp(0, 2).toInt();
    switch (exponent) {
      case 0:
        return ImageScale.s;
      case 1:
        return ImageScale.m;
      case 2:
        return ImageScale.l;
      default:
        // This case is unreachable due to the clamp function.
        return ImageScale.s;
    }
  }

  /// Returns a copy of this [ResponsiveFrameworkData] recalculated for a specific width.
  /// This enables "Container Queries" where a widget determines its layout based on
  /// its available width rather than the global screen width.
  ResponsiveFrameworkData copyForWidth(double width) {
    // 1. Adjusted width (honoring the user's text scale settings)
    final adjustedWidth =
        ResponsiveUtils.calculateReducedScreenWidthByTextScaler(
      originalWidth: width,
      textScalerFactor: currentTextScale,
    );

    // 2. Find which breakpoint name this width maps to
    final newBreakpoint = breakpoints.firstWhereOrNull(
          (bp) => adjustedWidth >= bp.start && adjustedWidth <= bp.end,
        ) ??
        (breakpoints.isNotEmpty
            ? breakpoints.first
            : const Breakpoint(start: 0, end: 0));

    // 3. Return a new instance with the flags recalculated
    return ResponsiveFrameworkData(
      screenWidth: adjustedWidth,
      screenHeight: screenHeight, // Device context stays
      breakpoint: newBreakpoint,
      breakpoints: breakpoints,
      isMobile: newBreakpoint.name == BreakpointName.mobile,
      isTablet: newBreakpoint.name == BreakpointName.tablet,
      isLaptop: newBreakpoint.name == BreakpointName.laptop,
      isDesktop: newBreakpoint.name == BreakpointName.desktop,
      isWide: newBreakpoint.name == BreakpointName.wide,
      orientation: orientation,
      baseScaleFactor: baseScaleFactor,
      effectiveTextScaleFactor: effectiveTextScaleFactor,
      currentTextScale: currentTextScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponsiveFrameworkData &&
          runtimeType == other.runtimeType &&
          screenWidth == other.screenWidth &&
          screenHeight == other.screenHeight &&
          breakpoint == other.breakpoint &&
          listEquals(breakpoints, other.breakpoints) &&
          isMobile == other.isMobile &&
          isTablet == other.isTablet &&
          isDesktop == other.isDesktop &&
          isWide == other.isWide &&
          orientation == other.orientation &&
          baseScaleFactor == other.baseScaleFactor &&
          effectiveTextScaleFactor == other.effectiveTextScaleFactor &&
          currentTextScale == other.currentTextScale;

  @override
  int get hashCode => Object.hash(
        screenWidth,
        screenHeight,
        breakpoint,
        Object.hashAll(breakpoints),
        isMobile,
        isTablet,
        isDesktop,
        isWide,
        orientation,
        baseScaleFactor,
        effectiveTextScaleFactor,
        currentTextScale,
      );
}

@immutable
class InheritedResponsiveFramework extends InheritedWidget {
  final ResponsiveFrameworkData data;

  const InheritedResponsiveFramework({
    super.key,
    required this.data,
    required super.child,
  });

  @override
  bool updateShouldNotify(InheritedResponsiveFramework oldWidget) =>
      data != oldWidget.data;
}

extension ResponsiveContextExtension on BuildContext {
  ResponsiveFrameworkData get responsive => ResponsiveFramework.of(this);
}

extension AdaptingEdgeInsetsExtension on EdgeInsetsGeometry {
  EdgeInsets adapt(BuildContext context) {
    final responsive = context.responsive;
    double adaptValue(double value) =>
        value == 0 ? 0 : responsive.adaptSize(value);
    final resolvedPadding = resolve(Directionality.maybeOf(context));
    return EdgeInsets.fromLTRB(
      adaptValue(resolvedPadding.left),
      adaptValue(resolvedPadding.top),
      adaptValue(resolvedPadding.right),
      adaptValue(resolvedPadding.bottom),
    );
  }
}

enum Conditional { largerThan, equals, smallerThan, between }

@immutable
class Condition<T> {
  final double? breakpointStart;
  final double? breakpointEnd;
  final BreakpointName? name;
  final Conditional? condition;
  final T value;

  const Condition._({
    this.breakpointStart,
    this.breakpointEnd,
    this.name,
    required this.condition,
    required this.value,
  }) : assert(
          (condition == Conditional.equals && name != null) ||
              (condition == Conditional.between &&
                  breakpointStart != null &&
                  breakpointEnd != null &&
                  breakpointStart <= breakpointEnd) ||
              ((condition == Conditional.largerThan ||
                      condition == Conditional.smallerThan) &&
                  (name != null || breakpointStart != null)),
          'Invalid Condition configuration.',
        );

  const Condition.equals({required this.name, required this.value})
      : breakpointStart = null,
        breakpointEnd = null,
        condition = Conditional.equals;

  const Condition.largerThan({
    double? breakpoint,
    this.name,
    required this.value,
  })  : assert(
          breakpoint != null || name != null,
          'Either breakpoint or name must be provided for largerThan',
        ),
        breakpointStart = breakpoint,
        breakpointEnd = null,
        condition = Conditional.largerThan;

  const Condition.smallerThan({
    double? breakpoint,
    this.name,
    required this.value,
  })  : assert(
          breakpoint != null || name != null,
          'Either breakpoint or name must be provided for smallerThan',
        ),
        breakpointStart = breakpoint,
        breakpointEnd = null,
        condition = Conditional.smallerThan;

  const Condition.between({
    required double start,
    required double end,
    required this.value,
  })  : assert(
          start <= end,
          'Start must be less than or equal to end for between condition',
        ),
        breakpointStart = start,
        breakpointEnd = end,
        name = null,
        condition = Conditional.between;

  Condition<T> copyWith({
    double? breakpointStart,
    double? breakpointEnd,
    BreakpointName? name,
    Conditional? condition,
    T? value,
  }) =>
      Condition<T>._(
        breakpointStart: breakpointStart ?? this.breakpointStart,
        breakpointEnd: breakpointEnd ?? this.breakpointEnd,
        name: name ?? this.name,
        condition: condition ?? this.condition,
        value: value ?? this.value,
      );

  @override
  String toString() =>
      'Condition(condition: $condition, name: ${name?.name}, breakpointStart: $breakpointStart, breakpointEnd: $breakpointEnd, value: $value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Condition<T> &&
          runtimeType == other.runtimeType &&
          breakpointStart == other.breakpointStart &&
          breakpointEnd == other.breakpointEnd &&
          name == other.name &&
          condition == other.condition &&
          value == other.value;

  @override
  int get hashCode =>
      Object.hash(breakpointStart, breakpointEnd, name, condition, value);
}

class ResponsiveValue<T> {
  final T value;

  ResponsiveValue(
    BuildContext context, {
    required T defaultValue,
    required List<Condition<T>> conditionalValues,
  }) : value = _calculateValue(context, conditionalValues, defaultValue);

  static T _calculateValue<T>(
    BuildContext context,
    List<Condition<T>> conditions,
    T defaultValue,
  ) {
    final ResponsiveFrameworkData responsiveData = context.responsive;
    final Condition<T>? activeCondition = conditions.lastWhereOrNull(
      (condition) => _isConditionMet(condition, responsiveData),
    );
    return activeCondition?.value ?? defaultValue;
  }

  static bool _isConditionMet<T>(
    Condition<T> condition,
    ResponsiveFrameworkData data,
  ) {
    switch (condition.condition) {
      case Conditional.equals:
        return data.breakpoint.name == condition.name!;
      case Conditional.between:
        return data.screenWidth >= condition.breakpointStart! &&
            data.screenWidth <= condition.breakpointEnd!;
      case Conditional.smallerThan:
        if (condition.name != null) {
          return data.smallerThan(condition.name!);
        } else if (condition.breakpointStart != null) {
          return data.screenWidth < condition.breakpointStart!;
        }
        return false;
      case Conditional.largerThan:
        if (condition.name != null) {
          return data.largerThan(condition.name!);
        } else if (condition.breakpointStart != null) {
          return data.screenWidth > condition.breakpointStart!;
        }
        return false;
      default:
        return false;
    }
  }
}

class AdaptingGap extends StatelessWidget {
  final double? width;
  final double? height;

  const AdaptingGap({super.key, this.width, this.height})
      : assert(
          width != null || height != null,
          'Either width or height must be provided.',
        );

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;
    final adaptedWidth =
        (width != null && width! > 0) ? responsive.adaptSize(width!) : width;
    final adaptedHeight = (height != null && height! > 0)
        ? responsive.adaptSize(height!)
        : height;
    return SizedBox(width: adaptedWidth, height: adaptedHeight);
  }
}

class ResponsiveUtils {
  static const double k = 0.20;
  static const reductionRate = 0.5; // Reverted from TextScaler specific usage
  static const double baseUndampenedFontSize = 15.0;
  static const double _defaultTextStyleFontSize = 14.0;

  static double calculateScaledFontSize({
    required double originalSize,
    required double scaleFactor,
  }) {
    if (originalSize < 0) return 0;
    if (scaleFactor <= 0) return 0;
    if (scaleFactor == 1.0) return originalSize;
    double dampeningInput = max(0, originalSize - baseUndampenedFontSize);
    double denominator = 1.0 + k * sqrt(dampeningInput);
    if (denominator.abs() < 1e-9) {
      denominator = 1.0;
    }
    double effectiveScaleIncrease = (scaleFactor - 1) / denominator;
    double scaledSize = originalSize * (1.0 + effectiveScaleIncrease);
    return max(0, scaledSize);
  }

  static double calculatePreScaledLogicalSize({
    required double targetLogicalSize,
    required double scaleFactor,
  }) {
    if (targetLogicalSize < 0) {
      debugPrint(
        'Warning: Negative targetLogicalSize ($targetLogicalSize) provided. Returning 0.',
      );
      return 0;
    }
    if (scaleFactor <= 0) {
      debugPrint(
        'Warning: Non-positive scaleFactor ($scaleFactor) provided. Returning 0.',
      );
      return 0;
    }
    if (scaleFactor == 1.0) return targetLogicalSize;
    double forwardDampeningInput = targetLogicalSize;
    double forwardDenominator = 1.0 + k * sqrt(max(0, forwardDampeningInput));
    if (forwardDenominator.abs() < 1e-9) {
      forwardDenominator = 1.0;
    }
    double forwardScaledSize = targetLogicalSize +
        (targetLogicalSize * (scaleFactor - 1)) / forwardDenominator;
    forwardScaledSize = max(0, forwardScaledSize);
    double approximatedBaseLogicalSize = forwardScaledSize / scaleFactor;
    return max(0, approximatedBaseLogicalSize);
  }

  // Reverted to using textScalerFactor (double) as per your request
  static double calculateReducedScreenWidthByTextScaler({
    required double originalWidth,
    required double textScalerFactor,
  }) {
    final double excessScale = max(0, textScalerFactor - 1.0);
    return originalWidth * (1.0 - excessScale * reductionRate);
  }

  static double calculatePreScaledFontSize({
    required double targetSize,
    required double scaleFactor,
  }) {
    if (targetSize < 0) {
      debugPrint(
        'Warning: Negative targetSize ($targetSize) provided. Returning 0.',
      );
      return 0;
    }
    if (scaleFactor <= 0) {
      debugPrint(
        'Warning: Non-positive scaleFactor ($scaleFactor) provided. Returning 0.',
      );
      return 0;
    }
    if (scaleFactor == 1.0) return targetSize;
    double forwardScaledSize = calculateScaledFontSize(
      originalSize: targetSize,
      scaleFactor: scaleFactor,
    );
    double approximatedBaseSize = forwardScaledSize / scaleFactor;
    return max(0, approximatedBaseSize);
  }

  static double calculatePreScaledTextScaleFactor({
    required double originalBaseFontSize,
    required double effectiveScaleFactor,
  }) {
    if (originalBaseFontSize <= 0) {
      debugPrint(
        'Warning: Non-positive originalBaseFontSize ($originalBaseFontSize) provided. Returning 1.0.',
      );
      return 1.0;
    }
    if (effectiveScaleFactor <= 0) {
      debugPrint(
        'Warning: Non-positive effectiveScaleFactor ($effectiveScaleFactor) provided. Returning 0.',
      );
      return 0;
    }
    if (effectiveScaleFactor == 1.0) return 1.0;
    double finalTargetFontSize = calculateScaledFontSize(
      originalSize: originalBaseFontSize,
      scaleFactor: effectiveScaleFactor,
    );
    double denominatorForFactor = originalBaseFontSize * effectiveScaleFactor;
    if (denominatorForFactor.abs() < 1e-9) {
      debugPrint(
        'Warning: Denominator near zero when calculating preScaleFactor. Returning 0.',
      );
      return 0;
    }
    double approximatedPreScaleFactor =
        finalTargetFontSize / denominatorForFactor;
    return max(0, approximatedPreScaleFactor);
  }

  static TextStyle? scaleTextStyle({
    required TextStyle? originalStyle,
    required double effectiveScaleFactor,
  }) {
    if (originalStyle == null) {
      return null;
    }
    final double originalFontSize =
        originalStyle.fontSize ?? _defaultTextStyleFontSize;
    if (originalFontSize <= 0) {
      return originalStyle;
    }
    final double preScaleFactor = calculatePreScaledTextScaleFactor(
      originalBaseFontSize: originalFontSize,
      effectiveScaleFactor: effectiveScaleFactor,
    );
    return originalStyle.apply(fontSizeFactor: preScaleFactor);
  }

  static TextTheme createScaledTextTheme({
    required TextTheme originalTextTheme,
    required double effectiveScaleFactor,
  }) {
    TextStyle? scaleStyle(TextStyle? style) => scaleTextStyle(
          originalStyle: style,
          effectiveScaleFactor: effectiveScaleFactor,
        );
    return TextTheme(
      displayLarge: scaleStyle(originalTextTheme.displayLarge),
      displayMedium: scaleStyle(originalTextTheme.displayMedium),
      displaySmall: scaleStyle(originalTextTheme.displaySmall),
      headlineLarge: scaleStyle(originalTextTheme.headlineLarge),
      headlineMedium: scaleStyle(originalTextTheme.headlineMedium),
      headlineSmall: scaleStyle(originalTextTheme.headlineSmall),
      titleLarge: scaleStyle(originalTextTheme.titleLarge),
      titleMedium: scaleStyle(originalTextTheme.titleMedium),
      titleSmall: scaleStyle(originalTextTheme.titleSmall),
      bodyLarge: scaleStyle(originalTextTheme.bodyLarge),
      bodyMedium: scaleStyle(originalTextTheme.bodyMedium),
      bodySmall: scaleStyle(originalTextTheme.bodySmall),
      labelLarge: scaleStyle(originalTextTheme.labelLarge),
      labelMedium: scaleStyle(originalTextTheme.labelMedium),
      labelSmall: scaleStyle(originalTextTheme.labelSmall),
    );
  }

  static int breakpointComparator(Breakpoint a, Breakpoint b) {
    return a.start.compareTo(b.start);
  }
}
