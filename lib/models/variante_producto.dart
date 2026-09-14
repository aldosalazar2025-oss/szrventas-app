import 'package:flutter/material.dart';
import '../utils/color_hex.dart';

/// Una combinación de talla y color dentro de un producto, con su
/// propio stock y (opcionalmente) su propio código de barras.
class VarianteProducto {
  final String talla;
  final String color;
  final String colorHex;
  final int stock;
  final String? codigoBarras;

  const VarianteProducto({
    required this.talla,
    required this.color,
    required this.colorHex,
    this.stock = 0,
    this.codigoBarras,
  });

  Color get colorObj => colorDesdeHex(colorHex);

  String get etiqueta => '$talla · $color';

  Map<String, dynamic> toMap() => {
        'talla': talla,
        'color': color,
        'colorHex': colorHex,
        'stock': stock,
        'codigoBarras': codigoBarras,
      };

  factory VarianteProducto.fromMap(Map<String, dynamic> map) {
    return VarianteProducto(
      talla: map['talla'] as String? ?? '',
      color: map['color'] as String? ?? '',
      colorHex: map['colorHex'] as String? ?? '#CCCCCC',
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      codigoBarras: map['codigoBarras'] as String?,
    );
  }

  VarianteProducto copyWith({
    String? talla,
    String? color,
    String? colorHex,
    int? stock,
    String? codigoBarras,
  }) {
    return VarianteProducto(
      talla: talla ?? this.talla,
      color: color ?? this.color,
      colorHex: colorHex ?? this.colorHex,
      stock: stock ?? this.stock,
      codigoBarras: codigoBarras ?? this.codigoBarras,
    );
  }
}
