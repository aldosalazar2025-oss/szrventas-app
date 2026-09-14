import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../models/variante_producto.dart';
import '../theme/app_theme.dart';

/// Muestra un selector de talla/color para productos con variantes.
/// Devuelve la [VarianteProducto] elegida, o null si se cancela.
///
/// [enCarrito] permite calcular cuánto de cada combinación ya está en el
/// carrito, para mostrar el stock realmente disponible.
Future<VarianteProducto?> showVarianteSelectorDialog({
  required BuildContext context,
  required Producto producto,
  required int Function(VarianteProducto variante) enCarrito,
}) {
  return showModalBottomSheet<VarianteProducto>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _VarianteSelectorSheet(
      producto: producto,
      enCarrito: enCarrito,
    ),
  );
}

class _VarianteSelectorSheet extends StatefulWidget {
  const _VarianteSelectorSheet({
    required this.producto,
    required this.enCarrito,
  });

  final Producto producto;
  final int Function(VarianteProducto variante) enCarrito;

  @override
  State<_VarianteSelectorSheet> createState() =>
      _VarianteSelectorSheetState();
}

class _VarianteSelectorSheetState extends State<_VarianteSelectorSheet> {
  String? _tallaSeleccionada;
  String? _colorSeleccionado;

  List<VarianteProducto> get _variantes => widget.producto.variantes;

  /// Tallas únicas que tiene este producto, en el orden en que aparecen.
  List<String> get _tallasDisponibles {
    final vistas = <String>{};
    final lista = <String>[];
    for (final v in _variantes) {
      if (v.talla.trim().isNotEmpty && vistas.add(v.talla)) lista.add(v.talla);
    }
    return lista;
  }

  /// Colores únicos que tiene este producto (con su variante de referencia
  /// para tomar el color visual), en el orden en que aparecen.
  List<VarianteProducto> get _coloresDisponibles {
    final vistos = <String>{};
    final lista = <VarianteProducto>[];
    for (final v in _variantes) {
      if (v.color.trim().isNotEmpty && vistos.add(v.color)) lista.add(v);
    }
    return lista;
  }

  int _disponibleVariante(VarianteProducto v) => v.stock - widget.enCarrito(v);

  /// Stock disponible sumando todos los colores de una talla.
  int _disponiblePorTalla(String talla) => _variantes
      .where((v) => v.talla == talla)
      .fold(0, (suma, v) => suma + _disponibleVariante(v));

  /// Stock disponible sumando todas las tallas de un color.
  int _disponiblePorColor(String color) => _variantes
      .where((v) => v.color == color)
      .fold(0, (suma, v) => suma + _disponibleVariante(v));

  /// La combinación exacta (talla + color) elegida, si existe entre las
  /// variantes configuradas del producto.
  VarianteProducto? get _varianteElegida {
    if (_tallaSeleccionada == null || _colorSeleccionado == null) return null;
    for (final v in _variantes) {
      if (v.talla == _tallaSeleccionada && v.color == _colorSeleccionado) {
        return v;
      }
    }
    return null;
  }

  String get _textoBoton {
    if (_tallaSeleccionada == null || _colorSeleccionado == null) {
      return 'Selecciona talla y color';
    }
    final v = _varianteElegida;
    if (v == null) return 'Esa combinación no existe';
    if (_disponibleVariante(v) <= 0) return 'Sin stock';
    return 'Agregar';
  }

  bool get _puedeAgregar {
    final v = _varianteElegida;
    return v != null && _disponibleVariante(v) > 0;
  }

  @override
  Widget build(BuildContext context) {
    final tallas = _tallasDisponibles;
    final colores = _coloresDisponibles;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.producto.nombre,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Elige talla y color',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_variantes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Este producto no tiene combinaciones configuradas',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tallas.isNotEmpty) ...[
                      const Text(
                        'Talla',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: tallas.map((t) {
                          final disponible = _disponiblePorTalla(t);
                          final agotada = disponible <= 0;
                          final seleccionada = _tallaSeleccionada == t;
                          return ChoiceChip(
                            label: Text(
                              '$t · $disponible und',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: seleccionada
                                    ? Colors.white
                                    : (agotada ? AppTheme.textMuted : AppTheme.textPrimary),
                              ),
                            ),
                            selected: seleccionada,
                            selectedColor: AppTheme.primary,
                            onSelected: agotada
                                ? null
                                : (_) => setState(() => _tallaSeleccionada = t),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (colores.isNotEmpty) ...[
                      const Text(
                        'Color',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: colores.map((v) {
                          final disponible = _disponiblePorColor(v.color);
                          final agotada = disponible <= 0;
                          final seleccionado = _colorSeleccionado == v.color;
                          return ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: v.colorObj,
                              radius: 9,
                            ),
                            label: Text(
                              '${v.color} · $disponible und',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: seleccionado
                                    ? Colors.white
                                    : (agotada ? AppTheme.textMuted : AppTheme.textPrimary),
                              ),
                            ),
                            selected: seleccionado,
                            selectedColor: AppTheme.primary,
                            onSelected: agotada
                                ? null
                                : (_) => setState(() => _colorSeleccionado = v.color),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed:
                  _puedeAgregar ? () => Navigator.pop(context, _varianteElegida) : null,
              child: Text(
                _textoBoton,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
