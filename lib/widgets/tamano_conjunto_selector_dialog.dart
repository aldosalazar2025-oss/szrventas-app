import 'package:flutter/material.dart';
import '../models/conjunto_opcion.dart';
import '../models/opcion_elegida.dart';
import '../models/producto.dart';
import '../models/tamano_producto.dart';
import '../theme/app_theme.dart';

/// Resultado del selector: el tamaño elegido (si el producto tiene
/// tamaños) y las opciones de conjuntos elegidas.
class SeleccionTamanoConjuntos {
  final TamanoProducto? tamano;
  final List<OpcionElegida> opciones;

  const SeleccionTamanoConjuntos({this.tamano, this.opciones = const []});
}

/// Muestra el selector de tamaño y conjuntos para un producto de
/// restaurante. Devuelve `null` si se cancela.
Future<SeleccionTamanoConjuntos?> showTamanoConjuntoSelectorDialog({
  required BuildContext context,
  required Producto producto,
}) {
  return showModalBottomSheet<SeleccionTamanoConjuntos>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TamanoConjuntoSheet(producto: producto),
  );
}

class _TamanoConjuntoSheet extends StatefulWidget {
  const _TamanoConjuntoSheet({required this.producto});

  final Producto producto;

  @override
  State<_TamanoConjuntoSheet> createState() => _TamanoConjuntoSheetState();
}

class _TamanoConjuntoSheetState extends State<_TamanoConjuntoSheet> {
  TamanoProducto? _tamano;
  // nombre del conjunto -> nombres de las opciones elegidas dentro de él.
  final Map<String, List<String>> _elegidas = {};

  @override
  void initState() {
    super.initState();
    if (widget.producto.tamanos.isNotEmpty) {
      _tamano = widget.producto.tamanos.first;
    }
    for (final c in widget.producto.conjuntos) {
      _elegidas[c.nombre] = [];
    }
  }

  bool get _puedeAgregar {
    if (widget.producto.tieneTamanos && _tamano == null) return false;
    for (final c in widget.producto.conjuntos) {
      if (c.obligatorio && (_elegidas[c.nombre]?.isEmpty ?? true)) {
        return false;
      }
    }
    return true;
  }

  double get _extrasTotal {
    double total = 0;
    for (final c in widget.producto.conjuntos) {
      final elegidas = _elegidas[c.nombre] ?? const [];
      for (final o in c.opciones) {
        if (elegidas.contains(o.nombre)) total += o.precioExtra;
      }
    }
    return total;
  }

  double get _precioBase => _tamano?.precio ?? widget.producto.precioVenta;

  /// Selección única dentro de un conjunto: tocar la opción ya elegida la
  /// quita (si el conjunto no es obligatorio); tocar otra la reemplaza.
  void _elegirUnica(ConjuntoOpcion conjunto, String opcion) {
    final actual = _elegidas[conjunto.nombre] ?? const [];
    if (actual.contains(opcion)) {
      if (conjunto.obligatorio) return;
      setState(() => _elegidas[conjunto.nombre] = []);
      return;
    }
    setState(() => _elegidas[conjunto.nombre] = [opcion]);
  }

  void _alternarMultiple(ConjuntoOpcion conjunto, String opcion) {
    final actuales = List<String>.from(_elegidas[conjunto.nombre] ?? const []);
    if (actuales.contains(opcion)) {
      setState(() {
        actuales.remove(opcion);
        _elegidas[conjunto.nombre] = actuales;
      });
      return;
    }
    if (conjunto.maximo != null && actuales.length >= conjunto.maximo!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Máximo ${conjunto.maximo} opciones en "${conjunto.nombre}"'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      actuales.add(opcion);
      _elegidas[conjunto.nombre] = actuales;
    });
  }

  void _confirmar() {
    final opciones = <OpcionElegida>[];
    for (final c in widget.producto.conjuntos) {
      final elegidas = _elegidas[c.nombre] ?? const [];
      for (final o in c.opciones) {
        if (elegidas.contains(o.nombre)) {
          opciones.add(OpcionElegida(
            conjunto: c.nombre,
            opcion: o.nombre,
            precioExtra: o.precioExtra,
          ));
        }
      }
    }
    Navigator.pop(
      context,
      SeleccionTamanoConjuntos(tamano: _tamano, opciones: opciones),
    );
  }

  Widget _chip({
    required String label,
    required bool seleccionada,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: seleccionada ? Colors.white : AppTheme.textPrimary,
        ),
      ),
      selected: seleccionada,
      selectedColor: AppTheme.primary,
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final producto = widget.producto;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
              producto.nombre,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Elige el tamaño y las opciones',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tamaños: se arman dinámicamente según lo configurado
                    // en "Tamaños y variantes" para este producto.
                    if (producto.tieneTamanos) ...[
                      const Text('Tamaño',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: producto.tamanos.map((t) {
                          final seleccionado = _tamano == t;
                          return _chip(
                            label: '${t.nombre} · S/ ${t.precio.toStringAsFixed(2)}',
                            seleccionada: seleccionado,
                            onTap: () => setState(() => _tamano = t),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 22),
                    ],
                    // Conjuntos (cremas, extras, etc.): cada uno se arma
                    // dinámicamente con las opciones que tenga configuradas.
                    for (final c in producto.conjuntos) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(c.nombre,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          if (c.obligatorio)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text(
                                'Obligatorio',
                                style: TextStyle(
                                  color: AppTheme.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        c.seleccionMultiple
                            ? (c.maximo != null
                                ? 'Elige hasta ${c.maximo}'
                                : 'Elige las que quieras')
                            : 'Elige una',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: c.opciones.map((o) {
                          final elegidas = _elegidas[c.nombre] ?? const [];
                          final seleccionada = elegidas.contains(o.nombre);
                          final label = o.precioExtra > 0
                              ? '${o.nombre} · + S/ ${o.precioExtra.toStringAsFixed(2)}'
                              : o.nombre;
                          return _chip(
                            label: label,
                            seleccionada: seleccionada,
                            onTap: () => c.seleccionMultiple
                                ? _alternarMultiple(c, o.nombre)
                                : _elegirUnica(c, o.nombre),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _puedeAgregar ? _confirmar : null,
                child: Text(
                  'Agregar · S/ ${(_precioBase + _extrasTotal).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
