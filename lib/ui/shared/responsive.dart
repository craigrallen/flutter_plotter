import 'package:flutter/widgets.dart';

enum LayoutSize { compact, medium, expanded }

class Responsive {
  static LayoutSize of(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return LayoutSize.compact;
    if (width < 840) return LayoutSize.medium;
    return LayoutSize.expanded;
  }

  static bool isTablet(BuildContext context) =>
      of(context) == LayoutSize.expanded;

  static bool isPhone(BuildContext context) =>
      of(context) == LayoutSize.compact;
}
