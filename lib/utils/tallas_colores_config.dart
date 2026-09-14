import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'color_hex.dart';

/// Un color disponible para armar combinaciones de producto.
class ColorOpcion {
  final String nombre;
  final String hex;

  const ColorOpcion(this.nombre, this.hex);

  Color get color => colorDesdeHex(hex);

  String toStorage() => '$nombre|$hex';

  static ColorOpcion fromStorage(String raw) {
    final partes = raw.split('|');
    return ColorOpcion(
      partes.isNotEmpty ? partes[0] : '',
      partes.length > 1 ? partes[1] : '#CCCCCC',
    );
  }
}

/// Configuración de "Tallas y colores": si la función está activa, y
/// las listas de tallas y colores disponibles para armar combinaciones
/// en el formulario de productos.
class TallasColoresConfig {
  static const prefsKeyHabilitado = 'tallas_colores_habilitado';
  static const prefsKeyTallas = 'tallas_colores_tallas';
  static const prefsKeyColores = 'tallas_colores_colores';

  static const List<String> tallasPorDefecto = [
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
  ];

  static const List<ColorOpcion> coloresPorDefecto = [
    ColorOpcion('Negro', '#212121'),
    ColorOpcion('Blanco', '#FFFFFF'),
    ColorOpcion('Rojo', '#E53935'),
    ColorOpcion('Azul', '#1E88E5'),
    ColorOpcion('Verde', '#43A047'),
    ColorOpcion('Beige', '#D7C4A3'),
  ];

  static Future<bool> estaHabilitado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKeyHabilitado) ?? false;
  }

  static Future<void> guardarHabilitado(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKeyHabilitado, valor);
  }

  static Future<List<String>> obtenerTallas() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKeyTallas) ?? List.from(tallasPorDefecto);
  }

  static Future<void> guardarTallas(List<String> tallas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKeyTallas, tallas);
  }

  static Future<List<ColorOpcion>> obtenerColores() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(prefsKeyColores);
    if (raw == null) return List.from(coloresPorDefecto);
    return raw.map(ColorOpcion.fromStorage).toList();
  }

  static Future<void> guardarColores(List<ColorOpcion> colores) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      prefsKeyColores,
      colores.map((c) => c.toStorage()).toList(),
    );
  }
}
