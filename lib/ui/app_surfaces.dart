import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

ColorScheme appSurfaceColors(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
    ? scheme
    : scheme.copyWith(
        surface: Colors.white,
        surfaceDim: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: Colors.white,
        surfaceBright: Colors.white,
        surfaceContainerHigh: const Color(0xFFF3F8FF),
        surfaceContainerHighest: const Color(0xFFE9F3FF),
      );

extension AppSurfaces on ColorScheme {
  Color get appChromeSurface =>
      brightness == Brightness.dark ? chromeSurface : Colors.white;

  BorderSide get cardEdge => brightness == Brightness.dark
      ? BorderSide.none
      : const BorderSide(color: Color(0xFFDEEBFA));
}
