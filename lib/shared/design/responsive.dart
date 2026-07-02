import 'package:flutter/widgets.dart';

import 'app_tokens.dart';

/// Window size class for the current layout width.
enum WindowSize { compact, medium, expanded }

/// Responsive helpers available on any [BuildContext].
extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  WindowSize get windowSize {
    final double w = _width;
    if (w < AppBreakpoints.compact) return WindowSize.compact;
    if (w < AppBreakpoints.medium) return WindowSize.medium;
    return WindowSize.expanded;
  }

  bool get isCompact => windowSize == WindowSize.compact;
  bool get isMedium => windowSize == WindowSize.medium;
  bool get isExpanded => windowSize == WindowSize.expanded;

  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// True on height-constrained windows (landscape phones), where vertical
  /// layouts must switch to side-by-side panes.
  bool get isCompactHeight => MediaQuery.sizeOf(this).height < 480;

  /// Picks a value per window size class, falling back leftward.
  T responsive<T>({required T compact, T? medium, T? expanded}) {
    return switch (windowSize) {
      WindowSize.compact => compact,
      WindowSize.medium => medium ?? compact,
      WindowSize.expanded => expanded ?? medium ?? compact,
    };
  }
}
