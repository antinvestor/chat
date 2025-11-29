/// Responsive breakpoints for adaptive layouts
class AppBreakpoints {
  // Prevent instantiation
  AppBreakpoints._();

  /// Mobile devices (< 600px)
  static const double mobile = 600.0;

  /// Tablet devices (600-900px)
  static const double tablet = 900.0;

  /// Desktop devices (> 900px)
  static const double desktop = 1200.0;

  /// Check if current width is mobile
  static bool isMobile(double width) => width < mobile;

  /// Check if current width is tablet
  static bool isTablet(double width) => width >= mobile && width < desktop;

  /// Check if current width is desktop
  static bool isDesktop(double width) => width >= desktop;
}

/// Helper extension for BuildContext
extension ResponsiveExtension on double {
  bool get isMobile => AppBreakpoints.isMobile(this);
  bool get isTablet => AppBreakpoints.isTablet(this);
  bool get isDesktop => AppBreakpoints.isDesktop(this);
}
