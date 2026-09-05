import 'package:flutter/material.dart';

class ResponsiveLayoutGuard extends StatelessWidget {
  final Widget mobileWidget;
  final Widget desktopWidget;
  
  /// The specific width threshold separating mobile constraints from desktop
  final double breakpoint;

  const ResponsiveLayoutGuard({
    super.key,
    required this.mobileWidget,
    required this.desktopWidget,
    this.breakpoint = 900.0,
  });

  @override
  Widget build(BuildContext context) {
    // We use a LayoutBuilder to dynamically evaluate constraints 
    // against the specified breakpoint without losing ancestor state metadata.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > breakpoint) {
          return desktopWidget;
        } else {
          return mobileWidget;
        }
      },
    );
  }
}
