import 'package:flutter/material.dart';

/// Central spacing, radius, and layout constants.
///
/// Keeping these in one place makes the design system consistent and easy to
/// tune. No widget should hard-code arbitrary spacing or dimensions.
abstract final class AppDimens {
  /// Spacing scale (4px base grid).
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Corner radii.
  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 24;
  static const double radiusCircle = 9999;

  /// Maximum content width for forms and cards on large/tablet screens.
  ///
  /// Content is centered within this width so forms never stretch awkwardly
  /// across a tablet or a landscape phone.
  static const double maxContentWidth = 440;

  /// Default horizontal page padding for auth screens.
  static const EdgeInsets authPagePadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: lg,
  );

  /// Minimum tappable target size (accessibility).
  static const Size minTapTarget = Size(48, 48);
}