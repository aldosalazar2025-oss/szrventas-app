import 'package:flutter/material.dart';

/// Padding para listas/scroll con margen extra sobre el área segura inferior.
EdgeInsets listBottomPadding(
  BuildContext context, {
  double horizontal = 16,
  double top = 16,
  double bottomExtra = 16,
}) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottomExtra + safeBottom);
}

/// Padding para formularios en scroll (auth, registro, etc.).
EdgeInsets formScrollPadding(
  BuildContext context, {
  double all = 24,
  double bottomExtra = 16,
}) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(all, all, all, all + bottomExtra + safeBottom);
}
