import '../utils/peso_formatter.dart';
import 'opcion_elegida.dart';
import 'producto.dart';

/// Modelo de Venta
class Venta {
  final String id;
  final List<ItemVenta> items;
  final double subtotal;
  final double descuento;
  final double total;
  final String metodoPago; // 'efectivo', 'yape', 'plin', 'tarjeta'
  final double? montoPagado;
  final double? vuelto;
  final DateTime fecha;
  final String? nota;

  Venta({
    required this.id,
    required this.items,
    required this.subtotal,
    this.descuento = 0,
    required this.total,
    required this.metodoPago,
    this.montoPagado,
    this.vuelto,
    DateTime? fecha,
    this.nota,
  }) : fecha = fecha ?? DateTime.now();

  /// Unidades sumadas + 1 por cada línea de peso (no suma gramos).
  int get totalItems => items.fold(0, (sum, item) => sum + (item.esPeso ? 1 : item.cantidad));

  double get gananciaTotal =>
      items.fold(0.0, (sum, item) => sum + item.gananciaTotal) - descuento;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subtotal': subtotal,
      'descuento': descuento,
      'total': total,
      'metodo_pago': metodoPago,
      'monto_pagado': montoPagado,
      'vuelto': vuelto,
      'fecha': fecha.toIso8601String(),
      'nota': nota,
    };
  }

  factory Venta.fromMap(Map<String, dynamic> map, List<ItemVenta> items) {
    return Venta(
      id: map['id'] as String,
      items: items,
      subtotal: (map['subtotal'] as num).toDouble(),
      descuento: (map['descuento'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num).toDouble(),
      metodoPago: map['metodo_pago'] as String,
      montoPagado: (map['monto_pagado'] as num?)?.toDouble(),
      vuelto: (map['vuelto'] as num?)?.toDouble(),
      fecha: DateTime.parse(map['fecha'] as String),
      nota: map['nota'] as String?,
    );
  }
}

/// Item individual dentro de una venta
class ItemVenta {
  final String id;
  final String ventaId;
  final String productoId;
  final String productoNombre;
  final String codigoBarras;
  final double precioUnitario;
  final double precioCompra;
  /// Unidades, o gramos si [esPeso].
  final int cantidad;
  final double subtotal;
  final String tipoVenta;
  final String? imagenUrl;
  /// Talla de la variante vendida (si el producto tiene tallas/colores).
  final String? varianteTalla;
  /// Color de la variante vendida (si el producto tiene tallas/colores).
  final String? varianteColor;
  /// Hex del color de la variante vendida, para mostrarlo en la UI.
  final String? varianteColorHex;
  /// Nombre del tamaño elegido (ej. "Familiar"), si el producto tiene tamaños.
  final String? tamanoNombre;
  /// Opciones de conjuntos elegidas (ej. cremas, extras) con su precio extra.
  final List<OpcionElegida> conjuntosElegidos;

  ItemVenta({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.productoNombre,
    required this.codigoBarras,
    required this.precioUnitario,
    required this.precioCompra,
    required this.cantidad,
    required this.subtotal,
    this.tipoVenta = TipoVenta.unidad,
    this.imagenUrl,
    this.varianteTalla,
    this.varianteColor,
    this.varianteColorHex,
    this.tamanoNombre,
    this.conjuntosElegidos = const [],
  });

  bool get esPeso => tipoVenta == TipoVenta.peso;

  /// true si esta línea corresponde a una combinación de talla/color.
  bool get tieneVariante =>
      (varianteTalla != null && varianteTalla!.trim().isNotEmpty) ||
      (varianteColor != null && varianteColor!.trim().isNotEmpty);

  /// Etiqueta legible de la variante, ej. "M · Rojo".
  String get etiquetaVariante {
    final partes = [varianteTalla, varianteColor]
        .where((e) => e != null && e.trim().isNotEmpty)
        .toList();
    return partes.join(' · ');
  }

  /// true si esta línea tiene un tamaño elegido.
  bool get tieneTamano => tamanoNombre != null && tamanoNombre!.trim().isNotEmpty;

  /// Suma de los precios extra de las opciones elegidas, por unidad.
  double get extrasPorUnidad =>
      conjuntosElegidos.fold(0.0, (s, o) => s + o.precioExtra);

  /// Firma canónica de los extras elegidos, para agrupar líneas del
  /// carrito que tienen exactamente la misma combinación.
  String get firmaExtras => OpcionElegida.firma(conjuntosElegidos);

  /// Etiqueta legible de las opciones elegidas, ej. "Mayonesa, Queso extra".
  String get etiquetaExtras =>
      conjuntosElegidos.map((o) => o.opcion).join(', ');

  String get formatoCantidad =>
      esPeso ? PesoFormatter.formatKg(cantidad) : 'x$cantidad';

  double get gananciaUnitaria => precioUnitario - precioCompra;

  double get gananciaTotal => esPeso
      ? PesoFormatter.subtotal(gramos: cantidad, precioPorKg: gananciaUnitaria)
      : gananciaUnitaria * cantidad;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'venta_id': ventaId,
      'producto_id': productoId,
      'producto_nombre': productoNombre,
      'codigo_barras': codigoBarras,
      'precio_unitario': precioUnitario,
      'precio_compra': precioCompra,
      'cantidad': cantidad,
      'subtotal': subtotal,
      'tipo_venta': tipoVenta,
      'variante_talla': varianteTalla,
      'variante_color': varianteColor,
      'variante_color_hex': varianteColorHex,
      'tamano_nombre': tamanoNombre,
      'tamano_precio': tieneTamano ? precioUnitario : null,
      'conjuntos_elegidos': conjuntosElegidos.isEmpty
          ? null
          : OpcionElegida.encodeLista(conjuntosElegidos),
    };
  }

  factory ItemVenta.fromMap(Map<String, dynamic> map) {
    return ItemVenta(
      id: map['id'] as String,
      ventaId: map['venta_id'] as String,
      productoId: map['producto_id'] as String,
      productoNombre: map['producto_nombre'] as String,
      codigoBarras: map['codigo_barras'] as String? ?? '',
      precioUnitario: (map['precio_unitario'] as num).toDouble(),
      precioCompra: (map['precio_compra'] as num).toDouble(),
      cantidad: (map['cantidad'] as num).toInt(),
      subtotal: (map['subtotal'] as num).toDouble(),
      tipoVenta: map['tipo_venta'] as String? ?? TipoVenta.unidad,
      imagenUrl: map['imagen_url'] as String?,
      varianteTalla: map['variante_talla'] as String?,
      varianteColor: map['variante_color'] as String?,
      varianteColorHex: map['variante_color_hex'] as String?,
      tamanoNombre: map['tamano_nombre'] as String?,
      conjuntosElegidos:
          OpcionElegida.decodeLista(map['conjuntos_elegidos'] as String?),
    );
  }

  ItemVenta copyWith({
    String? ventaId,
    int? cantidad,
    double? subtotal,
    String? tipoVenta,
  }) {
    return ItemVenta(
      id: id,
      ventaId: ventaId ?? this.ventaId,
      productoId: productoId,
      productoNombre: productoNombre,
      codigoBarras: codigoBarras,
      precioUnitario: precioUnitario,
      precioCompra: precioCompra,
      cantidad: cantidad ?? this.cantidad,
      subtotal: subtotal ?? this.subtotal,
      tipoVenta: tipoVenta ?? this.tipoVenta,
      imagenUrl: imagenUrl,
      varianteTalla: varianteTalla,
      varianteColor: varianteColor,
      varianteColorHex: varianteColorHex,
      tamanoNombre: tamanoNombre,
      conjuntosElegidos: conjuntosElegidos,
    );
  }
}
