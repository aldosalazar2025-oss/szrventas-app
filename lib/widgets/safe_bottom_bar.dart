import 'package:flutter/material.dart';

/// Barra inferior fija que respeta el área segura del sistema (gestos / navegación).
class SafeBottomBar extends StatelessWidget {
  const SafeBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.minimumBottom = 8,
    this.decoration,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double minimumBottom;
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: minimumBottom),
      child: DecoratedBox(
        decoration: decoration ?? const BoxDecoration(),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
