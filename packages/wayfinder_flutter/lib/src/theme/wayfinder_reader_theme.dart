import 'package:flutter/widgets.dart';

import '../model/knowledge_severity.dart';

const _captionStyle = TextStyle(fontSize: 12, height: 16 / 12);
const _smallRadius = Radius.circular(6);
const _mediumRadius = Radius.circular(8);

/// The colours and type a reader's widgets draw with.
///
/// A host maps its own design system onto these values; this package depends
/// on none. Start from [WayfinderReaderThemeData.dark] or
/// [WayfinderReaderThemeData.light] and use [copyWith], so a value added here
/// later keeps its default.
@immutable
final class WayfinderReaderThemeData {
  /// A theme with every colour given.
  const WayfinderReaderThemeData({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.mutedForeground,
    required this.popover,
    required this.popoverForeground,
    required this.border,
    required this.error,
    required this.warning,
    this.fontFamily,
    this.captionStyle = _captionStyle,
    this.smallRadius = _smallRadius,
    this.mediumRadius = _mediumRadius,
  });

  /// The default dark theme.
  const WayfinderReaderThemeData.dark({
    this.fontFamily,
    this.captionStyle = _captionStyle,
    this.smallRadius = _smallRadius,
    this.mediumRadius = _mediumRadius,
  }) : brightness = Brightness.dark,
       background = const Color(0xFF0A0A0A),
       foreground = const Color(0xFFFAFAFA),
       mutedForeground = const Color(0xFFA1A1A1),
       popover = const Color(0xFF171717),
       popoverForeground = const Color(0xFFFAFAFA),
       border = const Color(0x1AFFFFFF),
       error = const Color(0xFFFF6467),
       warning = const Color(0xFFFBBF24);

  /// The default light theme.
  const WayfinderReaderThemeData.light({
    this.fontFamily,
    this.captionStyle = _captionStyle,
    this.smallRadius = _smallRadius,
    this.mediumRadius = _mediumRadius,
  }) : brightness = Brightness.light,
       background = const Color(0xFFFFFFFF),
       foreground = const Color(0xFF0A0A0A),
       mutedForeground = const Color(0xFF707070),
       popover = const Color(0xFFFFFFFF),
       popoverForeground = const Color(0xFF0A0A0A),
       border = const Color(0xFFE5E5E5),
       error = const Color(0xFFE7000B),
       warning = const Color(0xFFB45309);

  /// Whether the colours are for a light or a dark surface.
  final Brightness brightness;

  /// The surface behind the content.
  final Color background;

  /// Primary text and emphasis.
  final Color foreground;

  /// Secondary text, lines and anything else that should stay quiet.
  final Color mutedForeground;

  /// The surface of cards that float over the content.
  final Color popover;

  /// Text on [popover].
  final Color popoverForeground;

  /// Hairlines around cards.
  final Color border;

  /// The colour of errors.
  final Color error;

  /// The colour of warnings.
  final Color warning;

  /// The family of text drawn on a canvas, or null for the platform's.
  final String? fontFamily;

  /// The smallest text step, colour aside.
  final TextStyle captionStyle;

  /// The corners of small floating cards.
  final Radius smallRadius;

  /// The corners of cards and controls.
  final Radius mediumRadius;

  /// [captionStyle] in [mutedForeground], whatever text style surrounds it.
  TextStyle get caption => captionStyle.copyWith(
    inherit: false,
    fontFamily: captionStyle.fontFamily ?? fontFamily,
    color: mutedForeground,
    decoration: TextDecoration.none,
  );

  /// The colour of [severity]: suggestions never colour anything.
  Color severityColor(KnowledgeSeverity severity) => switch (severity) {
    KnowledgeSeverity.error => error,
    KnowledgeSeverity.warning => warning,
    KnowledgeSeverity.suggestion => mutedForeground,
  };

  /// This theme with the given values replaced.
  WayfinderReaderThemeData copyWith({
    Brightness? brightness,
    Color? background,
    Color? foreground,
    Color? mutedForeground,
    Color? popover,
    Color? popoverForeground,
    Color? border,
    Color? error,
    Color? warning,
    String? fontFamily,
    TextStyle? captionStyle,
    Radius? smallRadius,
    Radius? mediumRadius,
  }) => WayfinderReaderThemeData(
    brightness: brightness ?? this.brightness,
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    popover: popover ?? this.popover,
    popoverForeground: popoverForeground ?? this.popoverForeground,
    border: border ?? this.border,
    error: error ?? this.error,
    warning: warning ?? this.warning,
    fontFamily: fontFamily ?? this.fontFamily,
    captionStyle: captionStyle ?? this.captionStyle,
    smallRadius: smallRadius ?? this.smallRadius,
    mediumRadius: mediumRadius ?? this.mediumRadius,
  );

  @override
  bool operator ==(Object other) =>
      other is WayfinderReaderThemeData &&
      other.brightness == brightness &&
      other.background == background &&
      other.foreground == foreground &&
      other.mutedForeground == mutedForeground &&
      other.popover == popover &&
      other.popoverForeground == popoverForeground &&
      other.border == border &&
      other.error == error &&
      other.warning == warning &&
      other.fontFamily == fontFamily &&
      other.captionStyle == captionStyle &&
      other.smallRadius == smallRadius &&
      other.mediumRadius == mediumRadius;

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    foreground,
    mutedForeground,
    popover,
    popoverForeground,
    border,
    error,
    warning,
    fontFamily,
    captionStyle,
    smallRadius,
    mediumRadius,
  );
}

/// Gives the widgets below it their [WayfinderReaderThemeData].
final class WayfinderReaderTheme extends InheritedWidget {
  /// Applies [data] to [child].
  const WayfinderReaderTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// The theme for the widgets below.
  final WayfinderReaderThemeData data;

  /// The nearest theme, or null when there is none.
  static WayfinderReaderThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WayfinderReaderTheme>()?.data;

  /// The nearest theme, or the default for the platform's brightness.
  static WayfinderReaderThemeData of(BuildContext context) =>
      maybeOf(context) ??
      (MediaQuery.maybePlatformBrightnessOf(context) == Brightness.light
          ? const WayfinderReaderThemeData.light()
          : const WayfinderReaderThemeData.dark());

  @override
  bool updateShouldNotify(WayfinderReaderTheme oldWidget) =>
      oldWidget.data != data;
}
