import 'package:flutter/material.dart';

/// Convierte un código hex (con o sin '#', ej. "#212121" o "212121")
/// a un [Color] de Flutter. Si el formato es inválido, devuelve gris.
Color colorDesdeHex(String hex) {
  var limpio = hex.trim().replaceFirst('#', '');
  if (limpio.length == 3) {
    limpio = limpio.split('').map((c) => '$c$c').join();
  }
  if (limpio.length != 6) return const Color(0xFFCCCCCC);
  final valor = int.tryParse('FF$limpio', radix: 16);
  return valor != null ? Color(valor) : const Color(0xFFCCCCCC);
}

/// Normaliza un texto ingresado por el usuario a un hex válido de 6
/// dígitos con '#' al inicio (ej. "e53935" -> "#E53935"), o null si
/// el formato no es válido.
String? normalizarHex(String texto) {
  var limpio = texto.trim().replaceFirst('#', '');
  if (limpio.length == 3) {
    limpio = limpio.split('').map((c) => '$c$c').join();
  }
  if (limpio.length != 6 || int.tryParse(limpio, radix: 16) == null) {
    return null;
  }
  return '#${limpio.toUpperCase()}';
}

/// Convierte un [Color] de Flutter a su código hex de 6 dígitos con '#'
/// al inicio (ej. Colors.red -> "#F44336"). Es el inverso de
/// [colorDesdeHex], útil cuando el color viene de un selector visual
/// (paleta/rueda de color) en vez de un texto escrito por el usuario.
String hexDesdeColor(Color color) {
  int canal(double c) => (c * 255).round().clamp(0, 255);
  final r = canal(color.r).toRadixString(16).padLeft(2, '0');
  final g = canal(color.g).toRadixString(16).padLeft(2, '0');
  final b = canal(color.b).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b'.toUpperCase();
}
